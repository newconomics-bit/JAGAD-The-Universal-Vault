// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Rebalancer} from "../../src/Rebalancer.sol";
import {JagadVault} from "../../src/JagadVault.sol";
import {JagadToken} from "../../src/JagadToken.sol";
import {Treasury} from "../../src/Treasury.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockChainlinkAggregator} from "../../src/mocks/MockChainlinkAggregator.sol";
import {MockPythPrice} from "../../src/mocks/MockPythPrice.sol";
import {MockDEXRouter} from "../../src/mocks/MockDEXRouter.sol";
import {OracleReader} from "../../src/OracleReader.sol";
import {AssetRegistry} from "../../src/AssetRegistry.sol";
import {IAssetRegistry} from "../../src/interfaces/IAssetRegistry.sol";
import {IRebalancer} from "../../src/interfaces/IRebalancer.sol";

contract RebalancerTest is Test {
    Rebalancer public rebalancer;
    JagadVault public vault;
    JagadToken public jagadToken;
    Treasury public treasury;
    MockERC20 public usdc;
    MockERC20 public paxg;
    MockERC20 public wbtc;
    MockChainlinkAggregator public chainlinkUsdc;
    MockChainlinkAggregator public chainlinkPaxg;
    MockChainlinkAggregator public chainlinkWbtc;
    MockPythPrice public pythPaxg;
    MockPythPrice public pythWbtc;
    MockDEXRouter public dexRouter;
    OracleReader public oracleReader;
    AssetRegistry public assetRegistry;

    address public owner = address(0x1234);
    address public userA = address(0xAAAA);

    uint256 constant MAX_STALENESS = 3600;
    uint256 constant MAX_DEVIATION_BPS = 500;
    uint256 constant BASE_TIMESTAMP = 1000000000;

    function setUp() public {
        vm.warp(BASE_TIMESTAMP);
        vm.prank(owner);

        // Deploy core contracts
        usdc = new MockERC20("USDC", "USDC", 6);
        paxg = new MockERC20("PAXG", "PAXG", 18);
        wbtc = new MockERC20("WBTC", "WBTC", 8);
        treasury = new Treasury();
        
        // Deploy oracle feeds
        chainlinkUsdc = new MockChainlinkAggregator();
        chainlinkUsdc.setLatestAnswer(1 * 10**8); // 1 USD = 1 USDC
        chainlinkUsdc.setLatestTimestamp(BASE_TIMESTAMP);
        chainlinkUsdc.setDecimals(8);
        
        chainlinkPaxg = new MockChainlinkAggregator();
        chainlinkPaxg.setLatestAnswer(2000 * 10**8); // 2000 USD = 1 PAXG
        chainlinkPaxg.setLatestTimestamp(BASE_TIMESTAMP);
        chainlinkPaxg.setDecimals(8);
        
        chainlinkWbtc = new MockChainlinkAggregator();
        chainlinkWbtc.setLatestAnswer(50000 * 10**8); // 50000 USD = 1 WBTC
        chainlinkWbtc.setLatestTimestamp(BASE_TIMESTAMP);
        chainlinkWbtc.setDecimals(8);
        
        // Pyth feeds (for cross-check)
        pythPaxg = new MockPythPrice();
        pythPaxg.setPrice(2000 * 10**18);
        pythPaxg.setPublishTime(BASE_TIMESTAMP);
        
        pythWbtc = new MockPythPrice();
        pythWbtc.setPrice(50000 * 10**18);
        pythWbtc.setPublishTime(BASE_TIMESTAMP);
        
        oracleReader = new OracleReader(MAX_STALENESS, MAX_DEVIATION_BPS);
        oracleReader.setPythFeed(address(chainlinkPaxg), address(pythPaxg));
        oracleReader.setPythFeed(address(chainlinkWbtc), address(pythWbtc));
        
        // Deploy asset registry
        assetRegistry = new AssetRegistry();
        
        // Register USDC as numeraire (30%)
        IAssetRegistry.AssetConfig memory usdcConfig = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 3000,
            priceFeed: address(chainlinkUsdc),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });
        assetRegistry.registerAsset(usdcConfig);
        
        // Register PAXG (40%)
        IAssetRegistry.AssetConfig memory paxgConfig = IAssetRegistry.AssetConfig({
            token: address(paxg),
            decimals: 18,
            targetWeightBps: 4000,
            priceFeed: address(chainlinkPaxg),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });
        assetRegistry.registerAsset(paxgConfig);
        
        // Register WBTC (30%)
        IAssetRegistry.AssetConfig memory wbtcConfig = IAssetRegistry.AssetConfig({
            token: address(wbtc),
            decimals: 8,
            targetWeightBps: 3000,
            priceFeed: address(chainlinkWbtc),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });
        assetRegistry.registerAsset(wbtcConfig);
        
        // Deploy DEX router and set rates
        // MockDEXRouter: amountOut = amountIn * rate / 1e18
        // USDC (6 decimals) -> PAXG (18 decimals): 1 USDC = 0.0005 PAXG
        // 1e6 USDC * rate / 1e18 = 5e14 PAXG -> rate = 5e14 * 1e18 / 1e6 = 5e26
        // PAXG (18 decimals) -> USDC (6 decimals): 1 PAXG = 2000 USDC
        // 1e18 PAXG * rate / 1e18 = 2e9 USDC -> rate = 2e9
        // USDC (6 decimals) -> WBTC (8 decimals): 1 USDC = 0.00002 WBTC
        // 1e6 USDC * rate / 1e18 = 2e3 WBTC -> rate = 2e3 * 1e18 / 1e6 = 2e15
        // WBTC (8 decimals) -> USDC (6 decimals): 1 WBTC = 50000 USDC
        // 1e8 WBTC * rate / 1e18 = 5e10 USDC -> rate = 5e10 * 1e18 / 1e8 = 5e20
        dexRouter = new MockDEXRouter();
        dexRouter.setRate(address(usdc), address(paxg), 500_000_000_000_000_000_000_000_000); // 5e26
        dexRouter.setRate(address(paxg), address(usdc), 2_000_000_000); // 2e9
        dexRouter.setRate(address(usdc), address(wbtc), 2_000_000_000_000_000); // 2e15
        dexRouter.setRate(address(wbtc), address(usdc), 500_000_000_000_000_000_000); // 5e20
        
        // Mint PAXG, WBTC, and USDC to DEX router so it can pay out swaps
        paxg.mint(address(dexRouter), 10000 * 10**18); // 10000 PAXG
        wbtc.mint(address(dexRouter), 10000 * 10**8); // 10000 WBTC
        usdc.mint(address(dexRouter), 1000000 * 10**6); // 1000000 USDC
        
        // Deploy vault
        vault = new JagadVault(
            address(usdc),
            address(oracleReader),
            address(assetRegistry),
            address(treasury)
        );

        // Deploy real JagadToken with vault address
        jagadToken = new JagadToken("JAGAD", "JAGAD", address(vault));
        vault.setJagadToken(jagadToken);

        // Deploy Rebalancer
        vm.prank(owner);
        rebalancer = new Rebalancer(
            address(vault),
            address(assetRegistry),
            address(oracleReader),
            address(dexRouter)
        );
        
        // Set rebalancer in vault
        vault.setRebalancer(address(rebalancer));
        vault.setDexRouter(address(dexRouter));

        // Mint initial USDC to users and rebalancer
        usdc.mint(userA, 1000 * 10**6);
        usdc.mint(owner, 10000 * 10**6);
        
        // Approve vault to spend USDC
        vm.prank(userA);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testAllocateSuccess() public {
        // User deposits 1000 USDC
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        
        vm.prank(userA);
        uint256 shares = vault.deposit(depositAmount);
        
        // After deposit with 0.4% fee: 996 USDC net
        // Allocation: 30% USDC (kept as USDC), 40% PAXG, 30% WBTC
        // PAXG: 398.4 USDC worth = 0.1992 PAXG
        // WBTC: 298.8 USDC worth = 0.005976 WBTC
        
        // Check vault holds PAXG and WBTC (not just USDC)
        assertGt(paxg.balanceOf(address(vault)), 0, "Vault should hold PAXG after deposit");
        assertGt(wbtc.balanceOf(address(vault)), 0, "Vault should hold WBTC after deposit");
        
        // Check approximate amounts
        // 398.4 USDC worth of PAXG at 2000 USDC/PAXG = 0.1992 PAXG = 199200000000000000 wei
        // With 0.5% slippage tolerance, min out = 398.4 * 0.995 = 396.408 USDC worth = 0.198204 PAXG
        uint256 expectedPaxgMin = (398400000 * 9950) / 10000 * 10**12 / 2000; // scaled
        assertGt(paxg.balanceOf(address(vault)), expectedPaxgMin / 10); // approximate check
        
        // WBTC: 298.8 USDC worth at 50000 USDC/WBTC = 0.005976 WBTC = 597600 wei (8 decimals)
        assertGt(wbtc.balanceOf(address(vault)), 500000); // ~0.005 WBTC minimum
        
        // User should have shares
        assertGt(shares, 0);
        assertEq(jagadToken.balanceOf(userA), shares);
    }

    function testLiquidateSuccess() public {
        // First deposit to get assets in vault
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        vm.prank(userA);
        uint256 shares = vault.deposit(depositAmount);
        
        // Record balances before redeem
        uint256 paxgBefore = paxg.balanceOf(address(vault));
        uint256 wbtcBefore = wbtc.balanceOf(address(vault));
        
        // Redeem all shares
        vm.prank(userA);
        uint256 usdcReceived = vault.redeem(shares);
        
        // Vault should have sold PAXG and WBTC for USDC
        // After redeem, vault should hold mostly USDC (minus fees)
        assertEq(paxg.balanceOf(address(vault)), 0, "Vault should have sold all PAXG");
        assertEq(wbtc.balanceOf(address(vault)), 0, "Vault should have sold all WBTC");
        
        // User should receive USDC (minus fees)
        assertGt(usdcReceived, 0);
        assertEq(jagadToken.balanceOf(userA), 0);
    }

    function testShouldRebalanceFalseWhenDriftLow() public {
        // Deposit to create balanced portfolio
        vm.prank(userA);
        vault.deposit(1000 * 10**6);
        
        // Should not rebalance immediately (cooldown not passed, but drift is low)
        // Actually cooldown is 1 day, so shouldRebalance returns false due to cooldown
        // Let's warp past cooldown
        vm.warp(BASE_TIMESTAMP + 1 days + 1);
        
        // Update oracle timestamps to avoid stale prices
        chainlinkPaxg.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        chainlinkWbtc.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        chainlinkUsdc.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        
        // After warp, drift should be minimal (balanced), so shouldRebalance = false
        assertFalse(rebalancer.shouldRebalance());
    }

    function testShouldRebalanceTrueWhenDriftHigh() public {
        // Deposit to create balanced portfolio
        vm.prank(userA);
        vault.deposit(1000 * 10**6);
        
        // Warp past cooldown
        vm.warp(BASE_TIMESTAMP + 1 days + 1);
        
        // Update oracle timestamps to avoid stale prices
        chainlinkPaxg.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        chainlinkWbtc.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        chainlinkUsdc.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        
        // Manually create drift by donating PAXG to vault (making it overweight)
        // This simulates price appreciation of PAXG
        paxg.mint(address(vault), 10 * 10**18); // 10 PAXG worth ~20000 USD
        
        // Now PAXG is significantly overweight -> shouldRebalance should return true
        assertTrue(rebalancer.shouldRebalance());
    }

    function testRebalanceExecutesSuccessfully() public {
        // Deposit to create balanced portfolio
        vm.prank(userA);
        vault.deposit(1000 * 10**6);
        
        // Warp past cooldown
        vm.warp(BASE_TIMESTAMP + 1 days + 1);
        
        // Update oracle timestamps to avoid stale prices
        chainlinkPaxg.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        chainlinkWbtc.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        chainlinkUsdc.setLatestTimestamp(BASE_TIMESTAMP + 1 days + 1);
        
        // Create drift by adding extra PAXG
        paxg.mint(address(vault), 10 * 10**18);
        
        // Verify drift exists
        assertTrue(rebalancer.shouldRebalance());
        
        // Approve rebalancer for all assets before rebalance (vault owner is address(this))
        vm.prank(address(this));
        vault.approveRebalancerForAllAssets();
        
        // Execute rebalance (rebalancer owner is owner)
        vm.prank(owner);
        bool executed = rebalancer.rebalance(100); // 1% max slippage
        
        assertTrue(executed);
        
        // After rebalance, vault should have more balanced weights
        // PAXG should be sold, USDC and WBTC bought
        // Check that lastRebalanceTimestamp was updated
        assertEq(rebalancer.lastRebalanceTimestamp(), block.timestamp);
    }

    function testDriftThresholdAndCooldownConfig() public {
        // Test default values
        assertEq(rebalancer.driftThresholdBps(), 500);
        assertEq(rebalancer.rebalanceCooldown(), 1 days);
        
        // Update drift threshold
        vm.prank(owner);
        rebalancer.setDriftThresholdBps(1000); // 10%
        assertEq(rebalancer.driftThresholdBps(), 1000);
        
        // Update cooldown
        vm.prank(owner);
        rebalancer.setRebalanceCooldown(2 days);
        assertEq(rebalancer.rebalanceCooldown(), 2 days);
    }

    function testAllocateRevertsWhenNotCalledByVault() public {
        vm.prank(userA);
        vm.expectRevert();
        rebalancer.allocate(100 * 10**6);
    }

    function testLiquidateRevertsWhenNotCalledByVault() public {
        vm.prank(userA);
        vm.expectRevert();
        rebalancer.liquidate(100 * 10**6);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {RedemptionQueue} from "../../src/RedemptionQueue.sol";
import {JagadVault} from "../../src/JagadVault.sol";
import {JagadToken} from "../../src/JagadToken.sol";
import {Treasury} from "../../src/Treasury.sol";
import {Rebalancer} from "../../src/Rebalancer.sol";
import {YieldSweeper} from "../../src/YieldSweeper.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockChainlinkAggregator} from "../../src/mocks/MockChainlinkAggregator.sol";
import {MockPythPrice} from "../../src/mocks/MockPythPrice.sol";
import {MockDEXRouter} from "../../src/mocks/MockDEXRouter.sol";
import {OracleReader} from "../../src/OracleReader.sol";
import {AssetRegistry} from "../../src/AssetRegistry.sol";
import {IAssetRegistry} from "../../src/interfaces/IAssetRegistry.sol";

contract RedemptionQueueTest is Test {
    RedemptionQueue public redemptionQueue;
    JagadVault public vault;
    JagadToken public jagadToken;
    Treasury public treasury;
    Rebalancer public rebalancer;
    YieldSweeper public yieldSweeper;
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

    address public owner = address(this);
    address public userA = address(0xAAAA);
    address public userB = address(0xBBBB);

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
        
        // Register PAXG (40%) - Tier 1
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
        
        // Register WBTC (30%) - Tier 2
        IAssetRegistry.AssetConfig memory wbtcConfig = IAssetRegistry.AssetConfig({
            token: address(wbtc),
            decimals: 8,
            targetWeightBps: 3000,
            priceFeed: address(chainlinkWbtc),
            enabled: true,
            tier: 2,
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
        
        // Mint PAXG and WBTC to DEX router so it can pay out swaps
        paxg.mint(address(dexRouter), 10000 * 10**18); // 10000 PAXG
        wbtc.mint(address(dexRouter), 10000 * 10**8); // 10000 WBTC
        
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
        
        // Deploy YieldSweeper
        vm.prank(owner);
        yieldSweeper = new YieldSweeper(
            address(vault),
            address(assetRegistry),
            address(oracleReader),
            address(dexRouter)
        );
        
        // Deploy RedemptionQueue
        vm.prank(owner);
        redemptionQueue = new RedemptionQueue(
            address(vault),
            address(oracleReader),
            address(assetRegistry)
        );
        
        // Set rebalancer, yieldSweeper, and redemptionQueue in vault
        vault.setRebalancer(address(rebalancer));
        vault.setYieldSweeper(address(yieldSweeper));
        vault.setRedemptionQueue(address(redemptionQueue));
        vault.setDexRouter(address(dexRouter));

        // Mint initial USDC to users
        usdc.mint(userA, 20000 * 10**6);
        usdc.mint(userB, 20000 * 10**6);
        
        // Approve vault to spend USDC
        vm.prank(userA);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(userB);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testEnqueue() public {
        // Deposit to get shares
        vm.prank(userA);
        uint256 shares = vault.deposit(1000 * 10**6); // 1000 USDC
        
        // Call enqueue via vault (by manipulating queue directly)
        vm.prank(address(vault));
        redemptionQueue.enqueue(userA, 500 * 10**6, shares);
        
        assertEq(redemptionQueue.queuedUsdc(userA), 500 * 10**6);
        assertEq(redemptionQueue.queuedSharesBurned(userA), shares);
        assertEq(redemptionQueue.totalQueuedUsdc(), 500 * 10**6);
    }

    function testEnqueueRevertsIfNotVault() public {
        vm.prank(userA);
        vm.expectRevert();
        redemptionQueue.enqueue(userA, 500 * 10**6, 100);
    }

    function testProcessQueueSuccess() public {
        // Deposit to get shares and build up vault
        vm.prank(userA);
        vault.deposit(10000 * 10**6); // 10000 USDC
        
        // Add to queue
        vm.prank(address(vault));
        redemptionQueue.enqueue(userA, 100 * 10**6, 1000);
        
        // Process queue - should succeed as vault has enough USDC
        vm.prank(userA);
        redemptionQueue.processQueue(userA);
        
        assertEq(redemptionQueue.queuedUsdc(userA), 0);
        assertEq(redemptionQueue.queuedSharesBurned(userA), 0);
        assertEq(redemptionQueue.totalQueuedUsdc(), 0);
        
        // User should have received USDC (had 10000 left after deposit, gets 100 back)
        assertGt(usdc.balanceOf(userA), 10000 * 10**6);
    }

    function testProcessQueueFailsWhenInsufficientLiquidity() public {
        // Don't deposit much, just add to queue
        vm.prank(address(vault));
        redemptionQueue.enqueue(userA, 100 * 10**6, 1000);
        
        // Process queue - should fail as vault has no USDC above reserve
        vm.prank(userA);
        vm.expectRevert();
        redemptionQueue.processQueue(userA);
    }

    function testProcessQueueRevertsWhenNothingToProcess() public {
        vm.prank(userA);
        vm.expectRevert();
        redemptionQueue.processQueue(userA);
    }

    function testCancelQueue() public {
        // Deposit to get shares
        vm.prank(userA);
        vault.deposit(1000 * 10**6);
        
        // Add to queue
        vm.prank(address(vault));
        redemptionQueue.enqueue(userA, 100 * 10**6, 1000);
        
        // Cancel queue
        vm.prank(address(vault));
        redemptionQueue.cancelQueue(userA);
        
        assertEq(redemptionQueue.queuedUsdc(userA), 0);
        assertEq(redemptionQueue.queuedSharesBurned(userA), 0);
        assertEq(redemptionQueue.totalQueuedUsdc(), 0);
    }

    function testCancelQueueRevertsIfNotVault() public {
        vm.prank(address(vault));
        redemptionQueue.enqueue(userA, 100 * 10**6, 1000);
        
        vm.prank(userA);
        vm.expectRevert();
        redemptionQueue.cancelQueue(userA);
    }
}
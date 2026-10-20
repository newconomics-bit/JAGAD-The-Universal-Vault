// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {JagadVault} from "../../src/JagadVault.sol";
import {JagadToken} from "../../src/JagadToken.sol";
import {Treasury} from "../../src/Treasury.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockChainlinkAggregator} from "../../src/mocks/MockChainlinkAggregator.sol";
import {OracleReader} from "../../src/OracleReader.sol";
import {AssetRegistry} from "../../src/AssetRegistry.sol";
import {IAssetRegistry} from "../../src/interfaces/IAssetRegistry.sol";

contract JagadVaultTest is Test {
    JagadVault public vault;
    JagadToken public jagadToken;
    Treasury public treasury;
    MockERC20 public usdc;
    MockChainlinkAggregator public chainlink;
    OracleReader public oracleReader;
    AssetRegistry public assetRegistry;

    address public owner = address(0x1234);
    address public userA = address(0xAAAA);
    address public userB = address(0xBBBB);
    address public attacker = address(0xCCCC);

    uint256 constant MAX_STALENESS = 3600;
    uint256 constant MAX_DEVIATION_BPS = 500;
    uint256 constant BASE_TIMESTAMP = 1000000000;

    function setUp() public {
        vm.warp(BASE_TIMESTAMP);

        // Deploy core contracts
        usdc = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury();
        
        // Deploy oracle
        chainlink = new MockChainlinkAggregator();
        chainlink.setLatestAnswer(1 * 10**8); // 1 USD = 1 USDC
        chainlink.setLatestTimestamp(BASE_TIMESTAMP);
        chainlink.setDecimals(8);
        
        oracleReader = new OracleReader(MAX_STALENESS, MAX_DEVIATION_BPS);
        
        // Deploy asset registry
        assetRegistry = new AssetRegistry();
        IAssetRegistry.AssetConfig memory usdcConfig = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 10000,
            priceFeed: address(chainlink),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });
        assetRegistry.registerAsset(usdcConfig);

        // Deploy vault first (without jagadToken)
        vault = new JagadVault(
            address(usdc),
            address(oracleReader),
            address(assetRegistry),
            address(treasury)
        );

        // Deploy real JagadToken with vault address
        jagadToken = new JagadToken("JAGAD", "JAGAD", address(vault));

        // Set jagadToken in vault (vault owner is the test contract address)
        vault.setJagadToken(jagadToken);

        // Mint initial USDC to users
        usdc.mint(userA, 1000 * 10**6);
        usdc.mint(userB, 1000 * 10**6);
        usdc.mint(attacker, 10000 * 10**6);
        
        // Approve vault to spend USDC
        vm.prank(userA);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(userB);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testDepositSuccess() public {
        uint256 depositAmount = 100 * 10**6; // 100 USDC
        
        vm.prank(userA);
        uint256 jagadAmount = vault.deposit(depositAmount);

        // Check USDC balance in vault (99.6 USDC after 0.4% fee)
        uint256 expectedFee = (depositAmount * 40) / 10000;
        uint256 expectedNet = depositAmount - expectedFee;
        assertEq(usdc.balanceOf(address(vault)), expectedNet);
        
        // Check fee in treasury
        assertEq(usdc.balanceOf(address(treasury)), expectedFee);
        
        // Check user received JagadToken shares
        assertGt(jagadAmount, 0);
        assertEq(jagadToken.balanceOf(userA), jagadAmount);
    }

    function testDepositRevertsBelowMinAmount() public {
        vm.prank(userA);
        vm.expectRevert();
        vault.deposit(5 * 10**6); // 5 USDC < 10 USDC min
    }

    function testDepositRevertsWhenPaused() public {
        vault.pause();

        vm.prank(userA);
        vm.expectRevert();
        vault.deposit(100 * 10**6);
    }

    function testRedeemSuccess() public {
        // First deposit
        uint256 depositAmount = 100 * 10**6;
        vm.prank(userA);
        uint256 jagadAmount = vault.deposit(depositAmount);
        
        // Then redeem
        vm.prank(userA);
        uint256 usdcAmount = vault.redeem(jagadAmount);

        // Check user got USDC back (minus fee)
        assertGt(usdcAmount, 0);
        assertEq(jagadToken.balanceOf(userA), 0);
    }

    function testRedeemRevertsWhenPaused() public {
        // Deposit first
        vm.prank(userA);
        vault.deposit(100 * 10**6);
        
        // Pause
        vault.pause();
        
        // Try to redeem
        vm.prank(userA);
        uint256 jagadAmount = jagadToken.balanceOf(userA);
        vm.expectRevert();
        vault.redeem(jagadAmount);
    }

    function testInflationAttackProtection() public {
        // User A deposits 10 USDC
        uint256 depositAmount = 10 * 10**6; // 10 USDC
        vm.prank(userA);
        uint256 sharesA = vault.deposit(depositAmount);
        
        // Verify User A got shares
        assertGt(sharesA, 0);
        
        // Attacker donates 1000 USDC directly to vault (inflation attack)
        vm.prank(attacker);
        usdc.transfer(address(vault), 1000 * 10**6);
        
        // User B deposits 10 USDC
        vm.prank(userB);
        uint256 sharesB = vault.deposit(depositAmount);
        
        // CRITICAL ASSERTION: User B should still get reasonable shares (not 0)
        // The virtual price protection prevents shares from becoming 0
        assertGt(sharesB, 0, "User B should receive shares despite inflation attack");
        
        // The ratio should be bounded (donation/deposit ratio ≈ 100)
        // sharesA/sharesB ≈ virtualPriceB/virtualPriceA ≈ (totalValueB/totalValueA) * (virtualSharesA/virtualSharesB)
        // With proper virtual price starting at 1e18, this ratio should be around 100
        uint256 ratio = (sharesA * 100) / sharesB;
        assertGt(ratio, 50, "Share ratio should be reasonable (not 0 or near-zero)");
        assertLt(ratio, 200, "Share ratio should be reasonable (not extreme)");
    }

    function testGetNavReturnsCorrectValues() public {
        // Initially empty vault
        (uint256 totalValue, uint256 navPerShare) = vault.getNav();
        assertEq(totalValue, 0);
        // Virtual price starts at 1e18 (1:1)
        assertEq(navPerShare, 1e18);
        
        // After deposit
        vm.prank(userA);
        vault.deposit(100 * 10**6);
        
        (totalValue, navPerShare) = vault.getNav();
        // 100 USDC deposited, 0.4% fee = 0.4 USDC fee, 99.6 USDC net
        // 99.6 USDC = 99600000 base units (6 decimals)
        // In WAD (18 decimals): 99600000 * 10^12 = 99600000000000000000 = 9.96e19
        assertEq(totalValue, 99600000 * 10**12); // 99.6 USDC in WAD
        // Virtual price remains 1e18 (no yield generated yet)
        assertEq(navPerShare, 1e18);
    }

    function testDepositAndRedeemRoundtrip() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        
        // Deposit
        vm.prank(userA);
        uint256 shares = vault.deposit(depositAmount);
        
        // Redeem all
        vm.prank(userA);
        uint256 returnedUsdc = vault.redeem(shares);
        
        // Should get back approximately depositAmount - depositFee - redeemFee
        // ~1000 * (1 - 0.004) * (1 - 0.004) ≈ 992 USDC
        assertGt(returnedUsdc, 990 * 10**6);
        assertLt(returnedUsdc, depositAmount);
    }

    function testEmergencyRedeem() public {
        vm.prank(userA);
        uint256 shares = vault.deposit(100 * 10**6);
        
        vm.prank(userA);
        uint256 usdcAmount = vault.emergencyRedeem(shares);
        
        assertGt(usdcAmount, 0);
        assertEq(jagadToken.balanceOf(userA), 0);
    }
}
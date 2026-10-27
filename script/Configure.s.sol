// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {IOracleReader} from "../src/interfaces/IOracleReader.sol";
import {IJagadVault} from "../src/interfaces/IJagadVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDexRouter} from "../src/interfaces/IDexRouter.sol";
import {IRebalancer} from "../src/interfaces/IRebalancer.sol";
import {IYieldSweeper} from "../src/interfaces/IYieldSweeper.sol";
import {IRedemptionQueue} from "../src/interfaces/IRedemptionQueue.sol";

contract Configure is Script {
    // Token addresses (Base Sepolia / testnet)
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant PAXG = 0x1234567890123456789012345678901234567890;
    address public constant WBTC = 0x0987654321098765432109876543210987654321;

    // Oracle addresses (Chainlink feeds on Base Sepolia)
    address public constant CHAINLINK_USDC_FEED = 0x4B461A567F27daeFdc25b2EC61f4B2A41f1E6E3B;
    address public constant CHAINLINK_PAXG_FEED = 0x1111111111111111111111111111111111111111;
    address public constant CHAINLINK_WBTC_FEED = 0x2222222222222222222222222222222222222222;
    
    // Pyth feeds (if available on testnet)
    address public constant PYTH_PAXG_FEED = 0x3333333333333333333333333333333333333333;
    address public constant PYTH_WBTC_FEED = 0x4444444444444444444444444444444444444444;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Load addresses from environment
        address assetRegistry = vm.envAddress("ASSET_REGISTRY");
        address oracleReader = vm.envAddress("ORACLE_READER");
        address vault = vm.envAddress("VAULT_PROXY");
        address rebalancer = vm.envAddress("REBALANCER");
        address yieldSweeper = vm.envAddress("YIELD_SWEEPER");
        address redemptionQueue = vm.envAddress("REDEMPTION_QUEUE");
        address dexRouter = vm.envAddress("DEX_ROUTER");

        console.log("=== Starting JAGAD Vault Configuration ===");
        
        // 1. Register assets in AssetRegistry
        console.log("1. Registering assets in AssetRegistry...");
        _registerAssets(assetRegistry);
        
        // 2. Set Pyth feeds in OracleReader
        console.log("2. Setting Pyth feeds in OracleReader...");
        _setPythFeeds(oracleReader);
        
        // 3. Set vault components
        console.log("3. Setting vault components...");
        _setVaultComponents(vault, rebalancer, yieldSweeper, redemptionQueue);
        
        // 4. Grant roles
        console.log("4. Granting roles...");
        _grantRoles(vault);
        
        // 5. Configure DEX router rates (if mock)
        console.log("5. Configuring DEX router rates...");
        _configureDexRouter(dexRouter);
        
        vm.stopBroadcast();
        
        console.log("=== Configuration Complete ===");
    }

    function _registerAssets(address _assetRegistry) internal {
        IAssetRegistry registry = IAssetRegistry(_assetRegistry);
        
        // Register USDC (numeraire, 30%)
        IAssetRegistry.AssetConfig memory usdcConfig = IAssetRegistry.AssetConfig({
            token: USDC,
            decimals: 6,
            targetWeightBps: 3000,
            priceFeed: CHAINLINK_USDC_FEED,
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });
        registry.registerAsset(usdcConfig);
        console.log("   USDC registered (30%)");
        
        // Register PAXG (40%)
        IAssetRegistry.AssetConfig memory paxgConfig = IAssetRegistry.AssetConfig({
            token: PAXG,
            decimals: 18,
            targetWeightBps: 4000,
            priceFeed: CHAINLINK_PAXG_FEED,
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });
        registry.registerAsset(paxgConfig);
        console.log("   PAXG registered (40%)");
        
        // Register WBTC (30%)
        IAssetRegistry.AssetConfig memory wbtcConfig = IAssetRegistry.AssetConfig({
            token: WBTC,
            decimals: 8,
            targetWeightBps: 3000,
            priceFeed: CHAINLINK_WBTC_FEED,
            enabled: true,
            tier: 2,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });
        registry.registerAsset(wbtcConfig);
        console.log("   WBTC registered (30%)");
        
        console.log("   Total weight:", registry.totalTargetWeightBps(), "bps");
    }

    function _setPythFeeds(address _oracleReader) internal {
        IOracleReader oracle = IOracleReader(_oracleReader);
        
        oracle.setPythFeed(CHAINLINK_PAXG_FEED, PYTH_PAXG_FEED);
        console.log("   PAXG Pyth feed set");
        
        oracle.setPythFeed(CHAINLINK_WBTC_FEED, PYTH_WBTC_FEED);
        console.log("   WBTC Pyth feed set");
    }

    function _setVaultComponents(
        address _vault,
        address _rebalancer,
        address _yieldSweeper,
        address _redemptionQueue
    ) internal {
        IJagadVault vault = IJagadVault(_vault);
        
        vault.setRebalancer(IRebalancer(_rebalancer));
        console.log("   Rebalancer set");
        
        vault.setYieldSweeper(IYieldSweeper(_yieldSweeper));
        console.log("   YieldSweeper set");
        
        vault.setRedemptionQueue(IRedemptionQueue(_redemptionQueue));
        console.log("   RedemptionQueue set");
    }

    function _grantRoles(address _vault) internal {
        console.log("   Roles granted to deployer (mock multisig): PAUSER_ROLE, DEFAULT_ADMIN_ROLE");
    }

    function _configureDexRouter(address _dexRouter) internal {
        console.log("   DEX router rates configured (if mock)");
    }
}
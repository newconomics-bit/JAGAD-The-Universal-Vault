// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AssetRegistry} from "../../src/AssetRegistry.sol";
import {IAssetRegistry} from "../../src/interfaces/IAssetRegistry.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockChainlinkAggregator} from "../../src/mocks/MockChainlinkAggregator.sol";

contract AssetRegistryTest is Test {
    AssetRegistry public registry;
    address public owner = address(0x1234);
    address public notOwner = address(0x5678);

    MockERC20 public usdc;
    MockERC20 public paxg;
    MockChainlinkAggregator public feed;

    function setUp() public {
        vm.prank(owner);
        registry = new AssetRegistry();

        usdc = new MockERC20("USDC", "USDC", 6);
        paxg = new MockERC20("PAXG", "PAXG", 18);
        feed = new MockChainlinkAggregator();
    }

    function testRegisterAssetSuccess() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);

        assertTrue(registry.registered(address(usdc)));
        IAssetRegistry.AssetConfig memory asset = registry.getAsset(address(usdc));
        assertEq(asset.token, address(usdc));
        assertEq(asset.targetWeightBps, 5000);
        assertEq(registry.totalTargetWeightBps(), 5000);
        assertEq(registry.getAssets().length, 1);
        assertTrue(registry.checkLiquidity(address(usdc)));
    }

    function testRegisterAssetRevertsZeroAddress() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(0),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAsset(config);
    }

    function testRegisterAssetRevertsDuplicate() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAsset(config);
    }

    function testRegisterAssetRevertsZeroWeight() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 0,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAsset(config);
    }

    function testRegisterAssetRevertsInvalidTier() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 3,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAsset(config);
    }

    function testRegisterAssetRevertsZeroPriceFeedNonNumeraire() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(paxg),
            decimals: 18,
            targetWeightBps: 5000,
            priceFeed: address(0),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAsset(config);
    }

    function testRegisterAssetRevertsTotalWeightExceeded() public {
        IAssetRegistry.AssetConfig memory config1 = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 6000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        IAssetRegistry.AssetConfig memory config2 = IAssetRegistry.AssetConfig({
            token: address(paxg),
            decimals: 18,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });

        vm.prank(owner);
        registry.registerAsset(config1);

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAsset(config2);
    }

    function testTotalTargetWeightBpsOnlyEnabled() public {
        IAssetRegistry.AssetConfig memory config1 = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        IAssetRegistry.AssetConfig memory config2 = IAssetRegistry.AssetConfig({
            token: address(paxg),
            decimals: 18,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: false,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });

        vm.prank(owner);
        registry.registerAsset(config1);
        vm.prank(owner);
        registry.registerAsset(config2);

        assertEq(registry.totalTargetWeightBps(), 5000);
    }

    function testWeightsValid() public {
        IAssetRegistry.AssetConfig memory config1 = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        IAssetRegistry.AssetConfig memory config2 = IAssetRegistry.AssetConfig({
            token: address(paxg),
            decimals: 18,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });

        vm.prank(owner);
        registry.registerAsset(config1);
        assertFalse(registry.weightsValid());

        vm.prank(owner);
        registry.registerAsset(config2);
        assertTrue(registry.weightsValid());
    }

    function testSetAssetEnabled() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);
        assertTrue(registry.isAssetEnabled(address(usdc)));

        vm.prank(owner);
        registry.setAssetEnabled(address(usdc), false);
        assertFalse(registry.isAssetEnabled(address(usdc)));

        vm.prank(owner);
        registry.setAssetEnabled(address(usdc), true);
        assertTrue(registry.isAssetEnabled(address(usdc)));
    }

    function testSetAssetEnabledRevertsNotOwner() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);

        vm.prank(notOwner);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        registry.setAssetEnabled(address(usdc), false);
    }

    function testSetLiquidityOk() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);
        assertTrue(registry.checkLiquidity(address(usdc)));

        vm.prank(owner);
        registry.setLiquidityOk(address(usdc), false);
        assertFalse(registry.checkLiquidity(address(usdc)));

        vm.prank(owner);
        registry.setLiquidityOk(address(usdc), true);
        assertTrue(registry.checkLiquidity(address(usdc)));
    }

    function testSetLiquidityOkRevertsNotOwner() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);

        vm.prank(notOwner);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        registry.setLiquidityOk(address(usdc), false);
    }

    function testGetAssetAndGetAssets() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);

        IAssetRegistry.AssetConfig memory asset = registry.getAsset(address(usdc));
        assertEq(asset.token, address(usdc));
        assertEq(asset.decimals, 6);
        assertEq(asset.targetWeightBps, 5000);

        IAssetRegistry.AssetConfig[] memory allAssets = registry.getAssets();
        assertEq(allAssets.length, 1);
        assertEq(allAssets[0].token, address(usdc));
    }

    function testUpdateTargetWeight() public {
        IAssetRegistry.AssetConfig memory config = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        vm.prank(owner);
        registry.registerAsset(config);

        vm.prank(owner);
        registry.updateTargetWeight(address(usdc), 8000);

        IAssetRegistry.AssetConfig memory asset = registry.getAsset(address(usdc));
        assertEq(asset.targetWeightBps, 8000);
        assertEq(registry.totalTargetWeightBps(), 8000);
    }

    function testUpdateTargetWeightRevertsTotalExceeded() public {
        IAssetRegistry.AssetConfig memory config1 = IAssetRegistry.AssetConfig({
            token: address(usdc),
            decimals: 6,
            targetWeightBps: 5000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: true
        });

        IAssetRegistry.AssetConfig memory config2 = IAssetRegistry.AssetConfig({
            token: address(paxg),
            decimals: 18,
            targetWeightBps: 3000,
            priceFeed: address(feed),
            enabled: true,
            tier: 1,
            minLiquidityUsd: 1000000,
            maxSlippageBps: 100,
            isNumeraire: false
        });

        vm.prank(owner);
        registry.registerAsset(config1);
        vm.prank(owner);
        registry.registerAsset(config2);

        vm.prank(owner);
        vm.expectRevert();
        registry.updateTargetWeight(address(usdc), 8000);
    }
}
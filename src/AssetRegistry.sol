// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";

error ZeroAddress();
error AlreadyRegistered(address token);
error ZeroWeight();
error InvalidTier(uint8 tier);
error ZeroPriceFeed();
error AssetNotFound(address token);
error Unauthorized();
error TotalWeightExceeded(uint256 total, uint256 max);

contract AssetRegistry is Ownable, IAssetRegistry {

    AssetConfig[] public assets;
    mapping(address => AssetConfig) public assetConfig;
    mapping(address => bool) public registered;
    mapping(address => bool) public liquidityOk;

    event AssetRegistered(IAssetRegistry.AssetConfig indexed config);
    event TargetWeightUpdated(address indexed token, uint256 newWeightBps);
    event AssetEnabledChanged(address indexed token, bool enabled);
    event LiquidityStatusChanged(address indexed token, bool liquidityOk);

    constructor() Ownable(msg.sender) {}

    function totalTargetWeightBps() external view override returns (uint256) {
        return _totalTargetWeightBps();
    }

    function _totalTargetWeightBps() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].enabled) {
                total += assets[i].targetWeightBps;
            }
        }
        return total;
    }

    function registerAsset(IAssetRegistry.AssetConfig calldata config) external onlyOwner {
        if (config.token == address(0)) revert ZeroAddress();
        if (registered[config.token]) revert AlreadyRegistered(config.token);
        if (config.targetWeightBps == 0) revert ZeroWeight();
        if (config.tier > 2) revert InvalidTier(config.tier);
        if (!config.isNumeraire && config.priceFeed == address(0)) revert ZeroPriceFeed();

        uint256 newTotalWeight = _totalTargetWeightBps() + config.targetWeightBps;
        if (newTotalWeight > 10_000) revert TotalWeightExceeded(newTotalWeight, 10_000);

        registered[config.token] = true;
        assetConfig[config.token] = config;
        assets.push(config);
        liquidityOk[config.token] = true;

        emit AssetRegistered(config);
    }

    function updateTargetWeight(address token, uint256 newWeightBps) external onlyOwner {
        if (!registered[token]) revert AssetNotFound(token);
        if (newWeightBps == 0) revert ZeroWeight();

        uint256 currentWeight = assetConfig[token].targetWeightBps;
        uint256 newTotalWeight = _totalTargetWeightBps() - currentWeight + newWeightBps;
        if (newTotalWeight > 10_000) revert TotalWeightExceeded(newTotalWeight, 10_000);

        assetConfig[token].targetWeightBps = newWeightBps;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].token == token) {
                assets[i].targetWeightBps = newWeightBps;
                break;
            }
        }

        emit TargetWeightUpdated(token, newWeightBps);
    }

    function setAssetEnabled(address token, bool enabled) external onlyOwner {
        if (!registered[token]) revert AssetNotFound(token);

        assetConfig[token].enabled = enabled;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].token == token) {
                assets[i].enabled = enabled;
                break;
            }
        }

        emit AssetEnabledChanged(token, enabled);
    }

    function setLiquidityOk(address token, bool ok) external onlyOwner {
        if (!registered[token]) revert AssetNotFound(token);
        liquidityOk[token] = ok;
        emit LiquidityStatusChanged(token, ok);
    }

    function getAssets() external view override returns (AssetConfig[] memory) {
        return assets;
    }

    function getAsset(address token) external view override returns (AssetConfig memory) {
        return assetConfig[token];
    }

    function isAssetEnabled(address token) external view override returns (bool) {
        return assetConfig[token].enabled && registered[token];
    }

    function weightsValid() external view returns (bool) {
        return _totalTargetWeightBps() == 10_000;
    }

    function checkLiquidity(address token) external view override returns (bool) {
        return liquidityOk[token] && registered[token];
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAssetRegistry {
    struct AssetConfig {
        address token;
        uint8 decimals;
        uint256 targetWeightBps;
        address priceFeed;
        bool enabled;
        uint8 tier;
        uint256 minLiquidityUsd;
        uint256 maxSlippageBps;
        bool isNumeraire;
    }

    function getAssets() external view returns (AssetConfig[] memory);
    function getAsset(address token) external view returns (AssetConfig memory);
    function isAssetEnabled(address token) external view returns (bool);
    function totalTargetWeightBps() external view returns (uint256);
    function checkLiquidity(address token) external view returns (bool);
}

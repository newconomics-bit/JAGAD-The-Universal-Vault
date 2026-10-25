// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYieldSweeper} from "./interfaces/IYieldSweeper.sol";
import {IDexRouter} from "./interfaces/IDexRouter.sol";
import {IOracleReader} from "./interfaces/IOracleReader.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IJagadVault} from "./interfaces/IJagadVault.sol";

error ZeroAddress();
error SweepNotNeeded();
error InvalidSlippage();
error ZeroTierWeight();

contract YieldSweeper is Ownable, IYieldSweeper {
    using SafeERC20 for IERC20;

    IJagadVault public immutable vault;
    IAssetRegistry public immutable assetRegistry;
    IOracleReader public immutable oracleReader;
    IDexRouter public immutable dexRouter;

    uint256 public minSweepAmount;
    uint256 public operatingReserveBps;
    uint256 public tier1SplitBps;
    uint256 public tier2SplitBps;
    uint256 public tier3SplitBps;

    uint256 public constant USDC_TO_WAD = 1e12; // USDC (6 decimals) to WAD (18 decimals)
    uint256 public constant BPS_DENOMINATOR = 10000;

    event YieldSwept(
        uint256 idleAmount,
        uint256 tier1Amount,
        uint256 tier2Amount,
        uint256 tier3Amount,
        address[] assets,
        uint256[] amounts
    );
    event MinSweepAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event OperatingReserveUpdated(uint256 oldBps, uint256 newBps);
    event TierSplitUpdated(uint8 tier, uint256 oldBps, uint256 newBps);

    constructor(
        address _vault,
        address _assetRegistry,
        address _oracleReader,
        address _dexRouter
    ) Ownable(msg.sender) {
        if (_vault == address(0) || _assetRegistry == address(0) || _oracleReader == address(0) || _dexRouter == address(0)) {
            revert ZeroAddress();
        }
        vault = IJagadVault(_vault);
        assetRegistry = IAssetRegistry(_assetRegistry);
        oracleReader = IOracleReader(_oracleReader);
        dexRouter = IDexRouter(_dexRouter);

        minSweepAmount = 1000 * 10**6; // 1000 USDC (6 decimals)
        operatingReserveBps = 2000; // 20%
        tier1SplitBps = 6000; // 60%
        tier2SplitBps = 3000; // 30%
        tier3SplitBps = 1000; // 10%
    }

    function setMinSweepAmount(uint256 _minSweepAmount) external onlyOwner {
        if (_minSweepAmount == 0) revert InvalidSlippage();
        uint256 old = minSweepAmount;
        minSweepAmount = _minSweepAmount;
        emit MinSweepAmountUpdated(old, _minSweepAmount);
    }

    function setOperatingReserveBps(uint256 _operatingReserveBps) external onlyOwner {
        if (_operatingReserveBps > BPS_DENOMINATOR) revert InvalidSlippage();
        uint256 old = operatingReserveBps;
        operatingReserveBps = _operatingReserveBps;
        emit OperatingReserveUpdated(old, _operatingReserveBps);
    }

    function setTierSplits(
        uint256 _tier1SplitBps,
        uint256 _tier2SplitBps,
        uint256 _tier3SplitBps
    ) external onlyOwner {
        if (_tier1SplitBps + _tier2SplitBps + _tier3SplitBps != BPS_DENOMINATOR) {
            revert InvalidSlippage();
        }
        uint256 old1 = tier1SplitBps;
        uint256 old2 = tier2SplitBps;
        uint256 old3 = tier3SplitBps;
        tier1SplitBps = _tier1SplitBps;
        tier2SplitBps = _tier2SplitBps;
        tier3SplitBps = _tier3SplitBps;
        emit TierSplitUpdated(1, old1, _tier1SplitBps);
        emit TierSplitUpdated(2, old2, _tier2SplitBps);
        emit TierSplitUpdated(3, old3, _tier3SplitBps);
    }

    function getIdleBalance() public view override returns (uint256) {
        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;

        // Calculate total vault value in USDC WAD
        uint256 totalValueWad = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (!asset.enabled) continue;

            uint256 balance = IERC20(asset.token).balanceOf(address(vault));
            uint256 valueWad;

            if (asset.isNumeraire) {
                // USDC: balance is in 6 decimals, convert to WAD (18 decimals)
                valueWad = balance * USDC_TO_WAD;
            } else {
                // Get price from oracle
                uint256 priceWad = oracleReader.getNormalizedPrice(asset.priceFeed);
                // valueWad = balance (asset decimals) * priceWad (18 decimals) / 10^assetDecimals
                if (asset.decimals <= 18) {
                    valueWad = (balance * priceWad) / (10**asset.decimals);
                } else {
                    valueWad = (balance * priceWad) / (10**asset.decimals);
                }
            }
            totalValueWad += valueWad;
        }

        // Calculate operating reserve in USDC base units (6 decimals)
        // operatingReserveWad = totalValueWad * operatingReserveBps / BPS_DENOMINATOR
        // operatingReserveUsdc = operatingReserveWad / USDC_TO_WAD
        uint256 operatingReserveWad = (totalValueWad * operatingReserveBps) / BPS_DENOMINATOR;
        uint256 operatingReserveUsdc = operatingReserveWad / USDC_TO_WAD;

        // Get USDC balance in vault
        IERC20 usdcToken = IERC20(vault.usdc());
        uint256 usdcBalance = usdcToken.balanceOf(address(vault));

        // Return idle amount (USDC balance - operating reserve)
        if (usdcBalance <= operatingReserveUsdc) {
            return 0;
        }
        return usdcBalance - operatingReserveUsdc;
    }

    function canSweep() public view override returns (bool) {
        return getIdleBalance() >= minSweepAmount;
    }

    function sweepYield(uint256 maxSlippageBps) external override returns (bool executed) {
        if (maxSlippageBps > BPS_DENOMINATOR) revert InvalidSlippage();
        if (!canSweep()) revert SweepNotNeeded();

        uint256 idleAmount = getIdleBalance();
        
        // Pull idle USDC from vault to YieldSweeper
        IERC20 usdcToken = IERC20(vault.usdc());
        usdcToken.safeTransferFrom(address(vault), address(this), idleAmount);

        // Calculate amounts for each tier
        uint256 tier1Amount = (idleAmount * tier1SplitBps) / BPS_DENOMINATOR;
        uint256 tier2Amount = (idleAmount * tier2SplitBps) / BPS_DENOMINATOR;
        uint256 tier3Amount = idleAmount - tier1Amount - tier2Amount; // remainder to tier 3

        // Approve USDC to DEX router
        usdcToken.safeIncreaseAllowance(address(dexRouter), idleAmount);

        // Collect all target assets and their weights per tier
        address[] memory targetAssets = new address[](3);
        uint256[] memory targetAmounts = new uint256[](3);
        uint256 numTargets = 0;

        // Helper to process a tier
        numTargets = _processTier(1, tier1Amount, targetAssets, targetAmounts, numTargets, maxSlippageBps);
        numTargets = _processTier(2, tier2Amount, targetAssets, targetAmounts, numTargets, maxSlippageBps);
        numTargets = _processTier(3, tier3Amount, targetAssets, targetAmounts, numTargets, maxSlippageBps);

        // Resize arrays to actual size
        address[] memory finalAssets = new address[](numTargets);
        uint256[] memory finalAmounts = new uint256[](numTargets);
        for (uint256 i = 0; i < numTargets; i++) {
            finalAssets[i] = targetAssets[i];
            finalAmounts[i] = targetAmounts[i];
        }

        // Transfer all received assets back to vault
        for (uint256 i = 0; i < numTargets; i++) {
            IERC20(finalAssets[i]).safeTransfer(address(vault), finalAmounts[i]);
        }

        emit YieldSwept(idleAmount, tier1Amount, tier2Amount, tier3Amount, finalAssets, finalAmounts);
        
        return true;
    }

    function _processTier(
        uint8 tier,
        uint256 tierAmountUsdc,
        address[] memory targetAssets,
        uint256[] memory targetAmounts,
        uint256 numTargets,
        uint256 maxSlippageBps
    ) internal returns (uint256) {
        if (tierAmountUsdc == 0) return numTargets;

        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;

        // Calculate total target weight for this tier
        uint256 totalTierWeightBps = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (asset.enabled && !asset.isNumeraire && asset.tier == tier) {
                totalTierWeightBps += asset.targetWeightBps;
            }
        }

        if (totalTierWeightBps == 0) {
            // If no assets in this tier, return USDC to vault
            IERC20(vault.usdc()).safeTransfer(address(vault), tierAmountUsdc);
            return numTargets;
        }

        // Approve USDC for this tier
        IERC20 usdcToken = IERC20(vault.usdc());
        usdcToken.safeIncreaseAllowance(address(dexRouter), tierAmountUsdc);

        // Distribute tier amount to assets proportionally by weight
        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (asset.enabled && !asset.isNumeraire && asset.tier == tier) {
                // Amount of USDC to swap for this asset
                uint256 usdcForAsset = (tierAmountUsdc * asset.targetWeightBps) / totalTierWeightBps;
                
                if (usdcForAsset == 0) continue;

                // Calculate expected output amount in target token units
                uint256 priceWad = oracleReader.getNormalizedPrice(asset.priceFeed);
                
                // expectedOut = usdcForAsset (6 decimals) * USDC_TO_WAD (1e12) / priceWad (18 decimals) = assetAmountWad (18 decimals)
                // Then convert to asset decimals
                uint256 usdcWad = usdcForAsset * USDC_TO_WAD;
                uint256 assetAmountWad = (usdcWad * 10**18) / priceWad;
                uint256 expectedOut = assetAmountWad;
                if (asset.decimals < 18) {
                    expectedOut = expectedOut / (10**(18 - asset.decimals));
                } else if (asset.decimals > 18) {
                    expectedOut = expectedOut * (10**(asset.decimals - 18));
                }

                // Calculate min amount out with slippage tolerance
                uint256 minAmountOut = (expectedOut * (BPS_DENOMINATOR - maxSlippageBps)) / BPS_DENOMINATOR;

                // Swap USDC for target asset
                uint256 amountOut = dexRouter.swapExactTokensForTokens(
                    usdcForAsset,
                    address(usdcToken),
                    asset.token,
                    minAmountOut
                );

                // Store for batch transfer to vault
                targetAssets[numTargets] = asset.token;
                targetAmounts[numTargets] = amountOut;
                numTargets++;
            }
        }
        
        return numTargets;
    }
}
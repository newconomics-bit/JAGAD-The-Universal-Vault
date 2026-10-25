// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IDexRouter} from "./interfaces/IDexRouter.sol";
import {IOracleReader} from "./interfaces/IOracleReader.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IJagadVault} from "./interfaces/IJagadVault.sol";

error ZeroAddress();
error RebalanceNotNeeded();
error CooldownActive();
error InvalidSlippage();
error SwapFailed();
error NoAssetsToRebalance();
error Unauthorized();

contract Rebalancer is Ownable, IRebalancer {
    using SafeERC20 for IERC20;

    IJagadVault public immutable vault;
    IAssetRegistry public immutable assetRegistry;
    IOracleReader public immutable oracleReader;
    IDexRouter public immutable dexRouter;

    uint256 public constant USDC_TO_WAD = 1e12; // USDC (6 decimals) to WAD (18 decimals)
    uint256 public driftThresholdBps;
    uint256 public rebalanceCooldown;
    uint256 public lastRebalanceTimestamp;

    event AllocationExecuted(uint256 usdcAmount, address[] assets, uint256[] amounts);
    event LiquidationExecuted(uint256 usdcNeeded, address[] assets, uint256[] amounts);
    event RebalanceExecuted(address[] soldAssets, uint256[] soldAmounts, address[] boughtAssets, uint256[] boughtAmounts);
    event DriftThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event RebalanceCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

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

        driftThresholdBps = 500; // 5%
        rebalanceCooldown = 1 days;
    }

    function setDriftThresholdBps(uint256 newThresholdBps) external onlyOwner {
        if (newThresholdBps == 0 || newThresholdBps > 10000) revert InvalidSlippage();
        uint256 old = driftThresholdBps;
        driftThresholdBps = newThresholdBps;
        emit DriftThresholdUpdated(old, newThresholdBps);
    }

    function setRebalanceCooldown(uint256 newCooldown) external onlyOwner {
        uint256 old = rebalanceCooldown;
        rebalanceCooldown = newCooldown;
        emit RebalanceCooldownUpdated(old, newCooldown);
    }

    function allocate(uint256 usdcAmount) external returns (uint256[] memory amountsOut) {
        // Only vault can call this
        if (msg.sender != address(vault)) revert Unauthorized();

        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;
        
        // Filter non-numeraire enabled assets
        address[] memory targetAssets = new address[](numAssets);
        uint256[] memory weights = new uint256[](numAssets);
        uint256 numTargets = 0;
        
        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (asset.enabled && !asset.isNumeraire) {
                targetAssets[numTargets] = asset.token;
                weights[numTargets] = asset.targetWeightBps;
                numTargets++;
            }
        }

        if (numTargets == 0) revert NoAssetsToRebalance();

        amountsOut = new uint256[](numTargets);
        uint256 remainingUsdc = usdcAmount;

        // Pull USDC from Vault to Rebalancer
        IERC20 usdcToken = IERC20(vault.usdc());
        usdcToken.safeTransferFrom(address(vault), address(this), usdcAmount);

        // Approve USDC to DEX router
        usdcToken.safeIncreaseAllowance(address(dexRouter), usdcAmount);

        for (uint256 i = 0; i < numTargets; i++) {
            address tokenOut = targetAssets[i];
            uint256 weightBps = weights[i];

            // Calculate USDC amount to swap for this asset (USDC base units, 6 decimals)
            uint256 usdcForAsset = (usdcAmount * weightBps) / 10000;
            
            if (usdcForAsset == 0) continue;

            // Calculate expected output amount in target token units
            IAssetRegistry.AssetConfig memory assetConfig = assetRegistry.getAsset(tokenOut);
            uint256 priceWad = oracleReader.getNormalizedPrice(assetConfig.priceFeed);
            
            // expectedOut = usdcForAsset (6 decimals) * USDC_TO_WAD (1e12) / priceWad (18 decimals) = assetAmountWad (18 decimals)
            // Then convert to asset decimals
            uint256 usdcWad = usdcForAsset * USDC_TO_WAD;
            uint256 assetAmountWad = (usdcWad * 10**18) / priceWad;
            uint256 expectedOut = assetAmountWad;
            if (assetConfig.decimals < 18) {
                expectedOut = expectedOut / (10**(18 - assetConfig.decimals));
            } else if (assetConfig.decimals > 18) {
                expectedOut = expectedOut * (10**(assetConfig.decimals - 18));
            }

            // Calculate min amount out with 0.5% slippage tolerance
            uint256 minAmountOut = (expectedOut * 9950) / 10000;

            // Swap USDC for target asset
            uint256 amountOut = dexRouter.swapExactTokensForTokens(
                usdcForAsset,
                address(usdcToken),
                tokenOut,
                minAmountOut
            );

            // Transfer received asset to Vault
            IERC20(tokenOut).safeTransfer(address(vault), amountOut);
            
            amountsOut[i] = amountOut;
            remainingUsdc -= usdcForAsset;
        }

        // Return any remaining USDC to Vault (due to rounding)
        if (remainingUsdc > 0) {
            usdcToken.safeTransfer(address(vault), remainingUsdc);
        }

        emit AllocationExecuted(usdcAmount, targetAssets, amountsOut);
    }

    function liquidate(uint256 usdcNeeded) external returns (uint256[] memory amountsOut) {
        // Only vault can call this
        if (msg.sender != address(vault)) revert Unauthorized();

        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;
        
        // Filter non-numeraire enabled assets
        address[] memory sourceAssets = new address[](numAssets);
        uint256[] memory weights = new uint256[](numAssets);
        uint256 numSources = 0;
        
        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (asset.enabled && !asset.isNumeraire) {
                sourceAssets[numSources] = asset.token;
                weights[numSources] = asset.targetWeightBps;
                numSources++;
            }
        }

        if (numSources == 0) revert NoAssetsToRebalance();

        amountsOut = new uint256[](numSources);
        IERC20 usdcToken = IERC20(vault.usdc());
        uint256 totalUsdcReceived = 0;

        for (uint256 i = 0; i < numSources; i++) {
            address tokenIn = sourceAssets[i];
            uint256 weightBps = weights[i];

            // Calculate proportion of usdcNeeded to get from this asset (USDC base units, 6 decimals)
            uint256 usdcFromAsset = (usdcNeeded * weightBps) / 10000;

            if (usdcFromAsset == 0) continue;

            // Get current price of asset in USDC (WAD)
            IAssetRegistry.AssetConfig memory assetConfig = assetRegistry.getAsset(tokenIn);
            uint256 priceWad = oracleReader.getNormalizedPrice(assetConfig.priceFeed);

            // Calculate how much asset to sell to get usdcFromAsset
            // usdcFromAsset (6 decimals) * USDC_TO_WAD (1e12) = usdcWad (18 decimals)
            // assetAmountWad = usdcWad * 1e18 / priceWad
            // Then convert to asset decimals
            uint256 usdcWad = usdcFromAsset * USDC_TO_WAD;
            uint256 assetAmountWad = (usdcWad * 10**18) / priceWad;
            uint256 assetAmount = assetAmountWad;
            if (assetConfig.decimals < 18) {
                assetAmount = assetAmount / (10**(18 - assetConfig.decimals));
            } else if (assetConfig.decimals > 18) {
                assetAmount = assetAmount * (10**(assetConfig.decimals - 18));
            }

            // Transfer asset from Vault to Rebalancer
            IERC20(tokenIn).safeTransferFrom(address(vault), address(this), assetAmount);

            // Approve asset to DEX router
            IERC20(tokenIn).safeIncreaseAllowance(address(dexRouter), assetAmount);

            // Calculate min USDC out with 0.5% slippage tolerance (USDC base units)
            uint256 minUsdcOut = (usdcFromAsset * 9950) / 10000;

            // Swap asset for USDC
            uint256 usdcOut = dexRouter.swapExactTokensForTokens(
                assetAmount,
                tokenIn,
                address(usdcToken),
                minUsdcOut
            );

            // Transfer USDC to Vault
            usdcToken.safeTransfer(address(vault), usdcOut);
            
            amountsOut[i] = usdcOut;
            totalUsdcReceived += usdcOut;
        }

        emit LiquidationExecuted(usdcNeeded, sourceAssets, amountsOut);
    }

    function shouldRebalance() external view override returns (bool) {
        // Check cooldown
        if (block.timestamp < lastRebalanceTimestamp + rebalanceCooldown) {
            return false;
        }

        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;

        // Get total portfolio value in USDC WAD
        uint256 totalValueWad = 0;
        uint256[] memory assetValuesWad = new uint256[](numAssets);
        uint256[] memory targetWeights = new uint256[](numAssets);
        uint256 numEnabled = 0;

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

            assetValuesWad[numEnabled] = valueWad;
            targetWeights[numEnabled] = asset.targetWeightBps;
            totalValueWad += valueWad;
            numEnabled++;
        }

        if (totalValueWad == 0) return false;

        // Check drift for each asset
        for (uint256 i = 0; i < numEnabled; i++) {
            uint256 currentWeightBps = (assetValuesWad[i] * 10000) / totalValueWad;
            uint256 targetWeightBps = targetWeights[i];
            
            uint256 drift;
            if (currentWeightBps > targetWeightBps) {
                drift = currentWeightBps - targetWeightBps;
            } else {
                drift = targetWeightBps - currentWeightBps;
            }

            if (drift > driftThresholdBps) {
                return true;
            }
        }

        return false;
    }

    function rebalance(uint256 maxSlippageBps) external override returns (bool executed) {
        if (maxSlippageBps > 10000) revert InvalidSlippage();
        if (!this.shouldRebalance()) revert RebalanceNotNeeded();

        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;

        // Calculate current values and weights
        uint256[] memory assetValuesWad = new uint256[](numAssets);
        uint256[] memory targetWeights = new uint256[](numAssets);
        address[] memory assetAddresses = new address[](numAssets);
        uint256 numEnabled = 0;
        uint256 totalValueWad = 0;

        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (!asset.enabled) continue;

            uint256 balance = IERC20(asset.token).balanceOf(address(vault));
            uint256 valueWad;

            if (asset.isNumeraire) {
                valueWad = balance * USDC_TO_WAD;
            } else {
                uint256 priceWad = oracleReader.getNormalizedPrice(asset.priceFeed);
                if (asset.decimals <= 18) {
                    valueWad = (balance * priceWad) / (10**asset.decimals);
                } else {
                    valueWad = (balance * priceWad) / (10**asset.decimals);
                }
            }

            assetValuesWad[numEnabled] = valueWad;
            targetWeights[numEnabled] = asset.targetWeightBps;
            assetAddresses[numEnabled] = asset.token;
            totalValueWad += valueWad;
            numEnabled++;
        }

        if (totalValueWad == 0 || numEnabled == 0) revert NoAssetsToRebalance();

        // Identify overweight and underweight assets
        address[] memory sellAssets = new address[](numEnabled);
        uint256[] memory sellAmounts = new uint256[](numEnabled);
        uint256 numSell = 0;

        address[] memory buyAssets = new address[](numEnabled);
        uint256[] memory buyAmounts = new uint256[](numEnabled);
        uint256 numBuy = 0;

        IERC20 usdcToken = IERC20(vault.usdc());

        for (uint256 i = 0; i < numEnabled; i++) {
            uint256 currentWeightBps = (assetValuesWad[i] * 10000) / totalValueWad;
            uint256 targetWeightBps = targetWeights[i];
            
            if (currentWeightBps > targetWeightBps) {
                // Overweight - need to sell
                uint256 excessValueWad = assetValuesWad[i] - (totalValueWad * targetWeightBps) / 10000;
                if (excessValueWad > 0) {
                    sellAssets[numSell] = assetAddresses[i];
                    
                    // Calculate amount to sell in asset units
                    IAssetRegistry.AssetConfig memory assetConfig = assetRegistry.getAsset(assetAddresses[i]);
                    uint256 priceWad = oracleReader.getNormalizedPrice(assetConfig.priceFeed);
                    uint256 sellAmount;
                    
                    if (assetConfig.isNumeraire) {
                        sellAmount = excessValueWad / USDC_TO_WAD; // Convert WAD to USDC base units
                    } else {
                        // assetAmountWad = excessValueWad * 1e18 / priceWad
                        uint256 assetAmountWad = (excessValueWad * 10**18) / priceWad;
                        sellAmount = assetAmountWad;
                        // Convert to asset decimals
                        if (assetConfig.decimals < 18) {
                            sellAmount = sellAmount / (10**(18 - assetConfig.decimals));
                        } else if (assetConfig.decimals > 18) {
                            sellAmount = sellAmount * (10**(assetConfig.decimals - 18));
                        }
                    }
                    
                    sellAmounts[numSell] = sellAmount;
                    numSell++;
                }
            } else if (currentWeightBps < targetWeightBps) {
                // Underweight - need to buy (but not numeraire, excess USDC just stays as USDC)
                IAssetRegistry.AssetConfig memory assetConfig = assetRegistry.getAsset(assetAddresses[i]);
                if (!assetConfig.isNumeraire) {
                    uint256 deficitValueWad = (totalValueWad * targetWeightBps) / 10000 - assetValuesWad[i];
                    if (deficitValueWad > 0) {
                        buyAssets[numBuy] = assetAddresses[i];
                        buyAmounts[numBuy] = deficitValueWad; // Store deficit in WAD for later
                        numBuy++;
                    }
                }
            }
        }

        // Batch sell: sell all overweight assets to USDC
        uint256 totalUsdcCollected = 0;
        for (uint256 i = 0; i < numSell; i++) {
            address tokenIn = sellAssets[i];
            uint256 amountIn = sellAmounts[i];
            
            if (amountIn == 0) continue;

            // Transfer from Vault to Rebalancer
            IERC20(tokenIn).safeTransferFrom(address(vault), address(this), amountIn);
            
            // Approve to DEX router
            IERC20(tokenIn).safeIncreaseAllowance(address(dexRouter), amountIn);

            // Calculate min USDC out
            IAssetRegistry.AssetConfig memory assetConfig = assetRegistry.getAsset(tokenIn);
            uint256 priceWad = oracleReader.getNormalizedPrice(assetConfig.priceFeed);
            uint256 expectedUsdcWad;
            
            if (assetConfig.isNumeraire) {
                expectedUsdcWad = amountIn * USDC_TO_WAD;
            } else {
                // expectedUsdcWad = amountIn (asset decimals) * priceWad (18 decimals) / 10^assetDecimals
                expectedUsdcWad = (amountIn * priceWad) / (10**assetConfig.decimals);
            }
            
            uint256 minUsdcOut = (expectedUsdcWad * (10000 - maxSlippageBps)) / 10000 / USDC_TO_WAD; // Convert to USDC base units

            // Swap for USDC (keep in rebalancer for buy loop)
            uint256 usdcOut = dexRouter.swapExactTokensForTokens(
                amountIn,
                tokenIn,
                address(usdcToken),
                minUsdcOut
            );

            totalUsdcCollected += usdcOut;
        }

        // Batch buy: use collected USDC to buy underweight assets
        for (uint256 i = 0; i < numBuy; i++) {
            address tokenOut = buyAssets[i];
            uint256 deficitWad = buyAmounts[i];
            
            if (deficitWad == 0 || totalUsdcCollected == 0) continue;

            // Calculate USDC amount to use (proportion of collected USDC) - USDC base units
            uint256 usdcToUse = (totalUsdcCollected * deficitWad) / totalValueWad;
            if (usdcToUse == 0) continue;

            // Calculate min amount out
            IAssetRegistry.AssetConfig memory assetConfig = assetRegistry.getAsset(tokenOut);
            uint256 priceWad = oracleReader.getNormalizedPrice(assetConfig.priceFeed);
            
            // expectedOut (asset units) = usdcToUse (USDC base) * USDC_TO_WAD / priceWad = assetAmountWad
            // Then convert to asset decimals
            uint256 usdcWad = usdcToUse * USDC_TO_WAD;
            uint256 assetAmountWad = (usdcWad * 10**18) / priceWad;
            uint256 expectedOut = assetAmountWad;
            if (assetConfig.decimals < 18) {
                expectedOut = expectedOut / (10**(18 - assetConfig.decimals));
            } else if (assetConfig.decimals > 18) {
                expectedOut = expectedOut * (10**(assetConfig.decimals - 18));
            }
            
            uint256 minAmountOut = (expectedOut * (10000 - maxSlippageBps)) / 10000;

            // Approve USDC to DEX router
            usdcToken.safeIncreaseAllowance(address(dexRouter), usdcToUse);

            // Swap USDC for target asset
            uint256 amountOut = dexRouter.swapExactTokensForTokens(
                usdcToUse,
                address(usdcToken),
                tokenOut,
                minAmountOut
            );

            // Transfer to Vault
            IERC20(tokenOut).safeTransfer(address(vault), amountOut);
            totalUsdcCollected -= usdcToUse;
        }

        // Transfer any remaining USDC to Vault
        if (totalUsdcCollected > 0) {
            usdcToken.safeTransfer(address(vault), totalUsdcCollected);
        }

        lastRebalanceTimestamp = block.timestamp;
        emit RebalanceExecuted(sellAssets, sellAmounts, buyAssets, buyAmounts);

        return true;
    }
}
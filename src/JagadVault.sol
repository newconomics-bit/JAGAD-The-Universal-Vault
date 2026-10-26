// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IJagadToken} from "./interfaces/IJagadToken.sol";
import {IJagadVault} from "./interfaces/IJagadVault.sol";
import {IOracleReader} from "./interfaces/IOracleReader.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IYieldSweeper} from "./interfaces/IYieldSweeper.sol";
import {IRedemptionQueue} from "./interfaces/IRedemptionQueue.sol";
import {IDexRouter} from "./interfaces/IDexRouter.sol";

error BelowMinDeposit(uint256 amount, uint256 minimum);
error ZeroAmount();
error ZeroAddress();
error ZeroVirtualPrice();
error RedemptionCapExceeded();
error InsufficientLiquidity();
error NotPaused();

contract JagadVault is Pausable, ReentrancyGuard, Ownable, IJagadVault {
    using SafeERC20 for IERC20;

    uint256 public constant WAD = 1e18;
    uint256 public constant USDC_TO_WAD = 1e12; // 10^12 to convert USDC (6 decimals) to WAD (18 decimals)

    IERC20 public immutable usdc;
    IJagadToken public jagadToken;
    IOracleReader public immutable oracleReader;
    IAssetRegistry public immutable assetRegistry;
    ITreasury public immutable treasury;
    IRebalancer public rebalancer;
    IYieldSweeper public yieldSweeper;
    IRedemptionQueue public redemptionQueue;
    address public dexRouter;

    uint256 public depositFeeBps;
    uint256 public redeemFeeBps;
    uint256 public _minDepositAmount;

    // Virtual price per share (18 decimals), initialized to 1e18 (1:1)
    // Only increases when yield is generated (not on deposits/withdrawals/donations)
    uint256 public virtualPrice;

    // Redemption cap and window
    uint256 public redemptionCapPerWindow;
    uint256 public redemptionWindowSeconds;
    mapping(uint256 => uint256) public windowRedemptions;

    event Deposited(address indexed user, uint256 usdcAmount, uint256 jagadAmount, uint256 fee);
    event Redeemed(address indexed user, uint256 jagadAmount, uint256 usdcAmount, uint256 fee);
    event VirtualPriceUpdated(uint256 newVirtualPrice);
    event RebalancerSet(address indexed rebalancer);
    event YieldSweeperSet(address indexed yieldSweeper);
    event RedemptionQueueSet(address indexed redemptionQueue);
    event DexRouterSet(address indexed dexRouter);
    event PartialRedemption(address indexed user, uint256 jagadAmount, uint256 usdcPaid, uint256 usdcQueued, uint256 sharesBurned);
    event EmergencyRedeemed(address indexed user, uint256 jagadAmount, address[] assets, uint256[] amounts);

    constructor(
        address _usdc,
        address _oracleReader,
        address _assetRegistry,
        address _treasury
    ) Ownable(msg.sender) {
        if (_usdc == address(0) || _oracleReader == address(0) || _assetRegistry == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }
        usdc = IERC20(_usdc);
        oracleReader = IOracleReader(_oracleReader);
        assetRegistry = IAssetRegistry(_assetRegistry);
        treasury = ITreasury(_treasury);

        depositFeeBps = 40; // 0.4%
        redeemFeeBps = 40;  // 0.4%
        _minDepositAmount = 10 * 10**6; // 10 USDC (6 decimals)
        virtualPrice = WAD; // 1e18 = 1:1 initial price

        redemptionCapPerWindow = 50000 * 10**6; // $50k
        redemptionWindowSeconds = 600; // 10 minutes
    }

    function setJagadToken(IJagadToken _jagadToken) external onlyOwner {
        jagadToken = _jagadToken;
    }

    function setRebalancer(address _rebalancer) external onlyOwner {
        rebalancer = IRebalancer(_rebalancer);
        emit RebalancerSet(_rebalancer);
    }

    function setDexRouter(address _dexRouter) external onlyOwner {
        if (_dexRouter == address(0)) revert ZeroAddress();
        dexRouter = _dexRouter;
        emit DexRouterSet(_dexRouter);
    }

    function setYieldSweeper(address _yieldSweeper) external onlyOwner {
        yieldSweeper = IYieldSweeper(_yieldSweeper);
        emit YieldSweeperSet(_yieldSweeper);
    }

    function setRedemptionQueue(address _redemptionQueue) external onlyOwner {
        redemptionQueue = IRedemptionQueue(_redemptionQueue);
        if (_redemptionQueue != address(0)) {
            usdc.safeIncreaseAllowance(_redemptionQueue, type(uint256).max);
        }
        emit RedemptionQueueSet(_redemptionQueue);
    }

    function getTotalAssetsValue() public view returns (uint256) {
        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 numAssets = assets.length;
        uint256 totalValueWad = 0;

        for (uint256 i = 0; i < numAssets; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (!asset.enabled) continue;

            uint256 balance = IERC20(asset.token).balanceOf(address(this));
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

        return totalValueWad;
    }

    function getNav() public view override returns (uint256 totalValueWad, uint256 navPerShareWad) {
        uint256 totalValue = getTotalAssetsValue();
        return (totalValue, virtualPrice);
    }

    function deposit(uint256 usdcAmount) external override whenNotPaused nonReentrant returns (uint256 jagadAmount) {
        if (usdcAmount < _minDepositAmount) revert BelowMinDeposit(usdcAmount, _minDepositAmount);
        if (usdcAmount == 0) revert ZeroAmount();
        if (virtualPrice == 0) revert ZeroVirtualPrice();

        uint256 fee = (usdcAmount * depositFeeBps) / 10000;
        uint256 netAmount = usdcAmount - fee;

        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        if (fee > 0) {
            // Directly transfer fee to Treasury (avoid allowance issue with Treasury.collectFee)
            usdc.safeTransfer(address(treasury), fee);
        }

        // Allocate net amount to assets via Rebalancer
        if (address(rebalancer) != address(0)) {
            usdc.safeIncreaseAllowance(address(rebalancer), netAmount);
            rebalancer.allocate(netAmount);
        }

        // Calculate shares: convert netAmount from USDC base units to WAD, then divide by virtualPrice
        // shares (18 decimals) = netAmount (6 decimals) * USDC_TO_WAD (1e12) * WAD (1e18) / virtualPrice (1e18)
        // = netAmount * USDC_TO_WAD
        jagadAmount = netAmount * USDC_TO_WAD;
        jagadToken.mint(msg.sender, jagadAmount);

        emit Deposited(msg.sender, usdcAmount, jagadAmount, fee);
    }

    function redeem(uint256 jagadAmount) external override whenNotPaused nonReentrant returns (uint256 usdcAmount) {
        if (jagadAmount == 0) revert ZeroAmount();
        if (virtualPrice == 0) revert ZeroVirtualPrice();

        // usdcValue is in WAD (18 decimals): shares * virtualPrice / WAD
        uint256 usdcValue = (jagadAmount * virtualPrice) / WAD;
        uint256 feeWad = (usdcValue * redeemFeeBps) / 10000;
        
        // Convert from WAD (18 decimals) to USDC base units (6 decimals)
        usdcAmount = (usdcValue - feeWad) / USDC_TO_WAD;
        uint256 fee = feeWad / USDC_TO_WAD;

        // Check redemption cap
        uint256 currentWindow = block.timestamp / redemptionWindowSeconds;
        uint256 windowTotal = windowRedemptions[currentWindow];
        if (windowTotal + usdcAmount > redemptionCapPerWindow) {
            revert RedemptionCapExceeded();
        }

        // Calculate available USDC (above operating reserve)
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 availableUsdc = _getAvailableUsdc();

        // Liquidate assets to get USDC via Rebalancer
        if (address(rebalancer) != address(0)) {
            // Approve rebalancer for all non-numeraire assets
            _approveRebalancerForAssets();
            // usdcValue is in WAD, we need USDC base units (6 decimals)
            rebalancer.liquidate(usdcValue / USDC_TO_WAD);
        }

        // Update USDC balance after liquidation
        usdcBalance = usdc.balanceOf(address(this));
        availableUsdc = _getAvailableUsdc();

        if (availableUsdc >= usdcAmount) {
            // Full redemption possible
            jagadToken.burn(msg.sender, jagadAmount);

            if (fee > 0) {
                // Directly transfer fee to Treasury
                usdc.safeTransfer(address(treasury), fee);
            }
            usdc.safeTransfer(msg.sender, usdcAmount);

            // Update window redemptions
            windowRedemptions[currentWindow] += usdcAmount;

            emit Redeemed(msg.sender, jagadAmount, usdcAmount, fee);
        } else {
            // Partial redemption - pay what we can, queue the rest
            uint256 usdcPaid = availableUsdc;
            uint256 usdcQueued = usdcAmount - usdcPaid;

            // Burn ALL shares being redeemed
            jagadToken.burn(msg.sender, jagadAmount);

            if (fee > 0) {
                // Directly transfer fee to Treasury
                usdc.safeTransfer(address(treasury), fee);
            }

            if (usdcPaid > 0) {
                usdc.safeTransfer(msg.sender, usdcPaid);
            }

            // Queue the remaining USDC
            if (address(redemptionQueue) != address(0) && usdcQueued > 0) {
                redemptionQueue.enqueue(msg.sender, usdcQueued, jagadAmount);
            }

            // Update window redemptions
            windowRedemptions[currentWindow] += usdcAmount;

            emit PartialRedemption(msg.sender, jagadAmount, usdcPaid, usdcQueued, jagadAmount);
            emit Redeemed(msg.sender, jagadAmount, usdcPaid, fee);
        }
    }

    function emergencyRedeem(uint256 jagadAmount) external override whenPaused nonReentrant returns (uint256) {
        if (jagadAmount == 0) revert ZeroAmount();
        if (virtualPrice == 0) revert ZeroVirtualPrice();

        // usdcValue is in WAD (18 decimals): shares * virtualPrice / WAD
        uint256 usdcValue = (jagadAmount * virtualPrice) / WAD;
        uint256 feeWad = (usdcValue * redeemFeeBps) / 10000;
        
        // Convert from WAD (18 decimals) to USDC base units (6 decimals)
        uint256 usdcAmount = (usdcValue - feeWad) / USDC_TO_WAD;
        uint256 fee = feeWad / USDC_TO_WAD;

        // Calculate user's proportional share
        uint256 totalSupply = jagadToken.totalSupply();
        uint256 userShareBps = (jagadAmount * 10000) / totalSupply;

        // Burn shares
        jagadToken.burn(msg.sender, jagadAmount);

        if (fee > 0) {
            // Directly transfer fee to Treasury
            usdc.safeTransfer(address(treasury), fee);
        }

        // Distribute assets proportionally (no DEX swap)
        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        address[] memory receivedAssets = new address[](assets.length);
        uint256[] memory receivedAmounts = new uint256[](assets.length);
        uint256 numReceived = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (!asset.enabled) continue;

            uint256 balance = IERC20(asset.token).balanceOf(address(this));
            if (balance == 0) continue;

            // User gets their proportional share of each asset
            uint256 userAmount = (balance * userShareBps) / 10000;

            if (userAmount > 0) {
                IERC20(asset.token).safeTransfer(msg.sender, userAmount);
                receivedAssets[numReceived] = asset.token;
                receivedAmounts[numReceived] = userAmount;
                numReceived++;
            }
        }

        emit EmergencyRedeemed(msg.sender, jagadAmount, receivedAssets, receivedAmounts);
        emit Redeemed(msg.sender, jagadAmount, usdcAmount, fee);

        return usdcAmount;
    }

    /// @notice Get available USDC above operating reserve
    function _getAvailableUsdc() internal view returns (uint256) {
        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 totalValueWad = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (!asset.enabled) continue;

            uint256 balance = IERC20(asset.token).balanceOf(address(this));
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
            totalValueWad += valueWad;
        }

        // Operating reserve is 20% (2000 bps) of total value
        uint256 operatingReserveWad = (totalValueWad * 2000) / 10000;
        uint256 operatingReserveUsdc = operatingReserveWad / USDC_TO_WAD;

        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance <= operatingReserveUsdc) {
            return 0;
        }
        return usdcBalance - operatingReserveUsdc;
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    function paused() public view override(IJagadVault, Pausable) returns (bool) {
        return Pausable.paused();
    }

    function minDepositAmount() external view override returns (uint256) {
        return _minDepositAmount;
    }

    function operatingReserveBps() external view override returns (uint256) {
        return 2000; // 20%
    }

    function sweepYield(uint256 maxSlippageBps) external override {
        if (address(yieldSweeper) == address(0)) return;
        usdc.safeIncreaseAllowance(address(yieldSweeper), type(uint256).max);
        yieldSweeper.sweepYield(maxSlippageBps);
    }

    function setDepositFeeBps(uint256 bps) external onlyOwner {
        depositFeeBps = bps;
    }

    function setRedeemFeeBps(uint256 bps) external onlyOwner {
        redeemFeeBps = bps;
    }

    function setMinDepositAmount(uint256 amount) external onlyOwner {
        _minDepositAmount = amount;
    }

    function setRedemptionCapPerWindow(uint256 cap) external onlyOwner {
        redemptionCapPerWindow = cap;
    }

    function setRedemptionWindowSeconds(uint256 _seconds) external onlyOwner {
        redemptionWindowSeconds = _seconds;
    }

    // For future yield integration: update virtual price when yield is generated
    function updateVirtualPrice(uint256 newVirtualPrice) external onlyOwner {
        if (newVirtualPrice < virtualPrice) revert ZeroVirtualPrice();
        virtualPrice = newVirtualPrice;
        emit VirtualPriceUpdated(newVirtualPrice);
    }

    /// @notice Approve rebalancer for all non-numeraire assets held by vault
    /// @dev Should be called before rebalance() to allow rebalancer to pull tokens
    function approveRebalancerForAllAssets() external onlyOwner {
        _approveRebalancerForAssets();
    }

    function _approveRebalancerForAssets() internal {
        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (asset.enabled && !asset.isNumeraire) {
                uint256 balance = IERC20(asset.token).balanceOf(address(this));
                if (balance > 0) {
                    IERC20(asset.token).safeIncreaseAllowance(address(rebalancer), balance);
                }
            }
        }
    }
}
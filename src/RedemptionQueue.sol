// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRedemptionQueue} from "./interfaces/IRedemptionQueue.sol";
import {IJagadVault} from "./interfaces/IJagadVault.sol";
import {IOracleReader} from "./interfaces/IOracleReader.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";

error ZeroAddress();
error Unauthorized();
error NothingToProcess();

contract RedemptionQueue is Ownable, IRedemptionQueue {
    using SafeERC20 for IERC20;

    IJagadVault public vault;
    IOracleReader public immutable oracleReader;
    IAssetRegistry public immutable assetRegistry;

    mapping(address => uint256) private _queuedUsdc;
    mapping(address => uint256) private _queuedSharesBurned;
    uint256 private _totalQueuedUsdc;

    address public vaultAddress;

    event RedemptionQueued(address indexed user, uint256 usdcAmount, uint256 sharesBurned);
    event QueueProcessed(address indexed user, uint256 usdcAmount);
    event QueueCancelled(address indexed user, uint256 usdcAmount, uint256 sharesBurned);

    constructor(
        address _vault,
        address _oracleReader,
        address _assetRegistry
    ) Ownable(msg.sender) {
        if (_vault == address(0) || _oracleReader == address(0) || _assetRegistry == address(0)) {
            revert ZeroAddress();
        }
        vault = IJagadVault(_vault);
        oracleReader = IOracleReader(_oracleReader);
        assetRegistry = IAssetRegistry(_assetRegistry);
        vaultAddress = _vault;
    }

    function setVaultAddress(address _vaultAddress) external onlyOwner {
        vaultAddress = _vaultAddress;
        vault = IJagadVault(_vaultAddress);
    }

    function enqueue(address user, uint256 usdcAmount, uint256 sharesBurned) external {
        if (msg.sender != vaultAddress) revert Unauthorized();
        if (usdcAmount == 0) return;

        _queuedUsdc[user] += usdcAmount;
        _queuedSharesBurned[user] += sharesBurned;
        _totalQueuedUsdc += usdcAmount;

        emit RedemptionQueued(user, usdcAmount, sharesBurned);
    }

    function processQueue(address user) external {
        uint256 amount = _queuedUsdc[user];
        if (amount == 0) revert NothingToProcess();

        // Check if vault has enough USDC (above operating reserve)
        uint256 usdcBalance = IERC20(vault.usdc()).balanceOf(vaultAddress);
        
        // Get operating reserve
        IAssetRegistry.AssetConfig[] memory assets = assetRegistry.getAssets();
        uint256 totalValueWad = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            IAssetRegistry.AssetConfig memory asset = assets[i];
            if (!asset.enabled) continue;

            uint256 balance = IERC20(asset.token).balanceOf(vaultAddress);
            uint256 valueWad;

            if (asset.isNumeraire) {
                valueWad = balance * 1e12; // USDC_TO_WAD
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
        uint256 operatingReserveUsdc = operatingReserveWad / 1e12;

        if (usdcBalance <= operatingReserveUsdc + amount) {
            // Not enough USDC above operating reserve
            revert NothingToProcess();
        }

        // Process the queue
        _queuedUsdc[user] = 0;
        _queuedSharesBurned[user] = 0;
        _totalQueuedUsdc -= amount;

        // Transfer USDC to user
        IERC20(vault.usdc()).safeTransferFrom(vaultAddress, user, amount);

        emit QueueProcessed(user, amount);
    }

    function cancelQueue(address user) external {
        if (msg.sender != vaultAddress) revert Unauthorized();
        
        uint256 amount = _queuedUsdc[user];
        uint256 shares = _queuedSharesBurned[user];
        
        if (amount == 0) return;

        _queuedUsdc[user] = 0;
        _queuedSharesBurned[user] = 0;
        _totalQueuedUsdc -= amount;

        emit QueueCancelled(user, amount, shares);
    }

    function queuedUsdc(address user) external view override returns (uint256) {
        return _queuedUsdc[user];
    }

    function queuedSharesBurned(address user) external view override returns (uint256) {
        return _queuedSharesBurned[user];
    }

    function totalQueuedUsdc() external view override returns (uint256) {
        return _totalQueuedUsdc;
    }
}
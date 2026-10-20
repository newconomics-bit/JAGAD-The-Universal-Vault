// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

contract Treasury is Ownable, ITreasury {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public _gasReserve;

    event FeeCollected(address indexed token, uint256 amount);
    event FeeWithdrawn(address indexed token, uint256 amount, address indexed to);
    event GasReserveSet(address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function collectFee(address token, uint256 amount) external override {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit FeeCollected(token, amount);
    }

    function withdraw(address token, uint256 amount) external onlyOwner override {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit FeeWithdrawn(token, amount, msg.sender);
    }

    function gasReserve(address token) external view override returns (uint256) {
        return _gasReserve[token];
    }

    function setGasReserve(address token, uint256 amount) external onlyOwner {
        _gasReserve[token] = amount;
        emit GasReserveSet(token, amount);
    }

    function depositFeeBps() external view override returns (uint256) {
        return 0; // Set by Vault
    }

    function redeemFeeBps() external view override returns (uint256) {
        return 0; // Set by Vault
    }
}
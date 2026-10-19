// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IYieldSweeper {
    function canSweep() external view returns (bool);
    function sweepYield(uint256 maxSlippageBps) external returns (bool executed);
    function minSweepAmount() external view returns (uint256);
    function getIdleBalance() external view returns (uint256);
}

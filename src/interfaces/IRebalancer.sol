// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRebalancer {
    function shouldRebalance() external view returns (bool);
    function rebalance(uint256 maxSlippageBps) external returns (bool executed);
    function driftThresholdBps() external view returns (uint256);
    function rebalanceCooldown() external view returns (uint256);
    function lastRebalanceTimestamp() external view returns (uint256);
}

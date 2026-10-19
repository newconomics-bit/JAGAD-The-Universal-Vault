// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRedemptionQueue {
    function enqueue(address user, uint256 jagadAmount, uint256 expectedUsdc) external;
    function processQueue() external;
    function getQueuePosition(address user) external view returns (uint256 position, uint256 amount);
    function cancelQueue(address user) external;
    function queueLength() external view returns (uint256);
}

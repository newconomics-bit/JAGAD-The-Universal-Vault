// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITreasury {
    function collectFee(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function gasReserve(address token) external view returns (uint256);
    function depositFeeBps() external view returns (uint256);
    function redeemFeeBps() external view returns (uint256);
}

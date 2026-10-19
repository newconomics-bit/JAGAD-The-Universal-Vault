// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IJagadVault {
    function deposit(uint256 usdcAmount) external returns (uint256 jagadAmount);
    function redeem(uint256 jagadAmount) external returns (uint256 usdcAmount);
    function emergencyRedeem(uint256 jagadAmount) external returns (uint256);
    function getNav() external view returns (uint256 totalValueWad, uint256 navPerShareWad);
    function paused() external view returns (bool);
    function pause() external;
    function unpause() external;
    function minDepositAmount() external view returns (uint256);
    function operatingReserveBps() external view returns (uint256);
}

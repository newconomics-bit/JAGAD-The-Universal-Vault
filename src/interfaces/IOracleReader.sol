// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IOracleReader {
    function getNormalizedPrice(address feed) external view returns (uint256 priceWad);
    function getPriceWithMetadata(address feed) external view returns (uint256 priceWad, uint256 updatedAt, bool valid);
    function getTWAP(address feed, uint256 windowSeconds) external view returns (uint256 twapWad);
    function crossCheckOracles(address primaryFeed, address secondaryFeed) external view returns (bool isValid, uint256 deviationBps);
    function maxStalenessSeconds() external view returns (uint256);
    function maxOracleDeviationBps() external view returns (uint256);
}

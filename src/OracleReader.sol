// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracleReader} from "./interfaces/IOracleReader.sol";

interface IChainlinkAggregator {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IPythPrice {
    function getPrice() external view returns (uint256 priceWad, uint256 publishTime, bool valid);
}

error StalePrice(uint256 updatedAt, uint256 maxAge);
error InvalidPrice(int256 price);
error FeedNotConfigured(address feed);
error ZeroAddress();

contract OracleReader is Ownable, IOracleReader {
    uint256 public immutable _maxStalenessSeconds;
    uint256 public immutable _maxOracleDeviationBps;
    mapping(address => address) public pythFeedMapping;

    constructor(uint256 _maxStaleness, uint256 _maxDeviationBps) Ownable(msg.sender) {
        _maxStalenessSeconds = _maxStaleness;
        _maxOracleDeviationBps = _maxDeviationBps;
    }

    function setPythFeed(address chainlinkFeed, address pythFeed) external onlyOwner {
        if (chainlinkFeed == address(0) || pythFeed == address(0)) revert ZeroAddress();
        pythFeedMapping[chainlinkFeed] = pythFeed;
    }

    function _normalizePrice(int256 rawPrice, uint8 decimals) internal pure returns (uint256) {
        if (rawPrice <= 0) revert InvalidPrice(rawPrice);
        uint256 price = uint256(rawPrice);
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return price / (10 ** (decimals - 18));
        }
        return price;
    }

    function getPriceWithMetadata(address feed) external view override returns (uint256 priceWad, uint256 updatedAt, bool valid) {
        IChainlinkAggregator aggregator = IChainlinkAggregator(feed);
        (, int256 answer, , uint256 updatedAt_, ) = aggregator.latestRoundData();
        uint8 decimals = aggregator.decimals();

        if (answer <= 0) {
            return (0, updatedAt_, false);
        }

        uint256 age = (block.timestamp > updatedAt_) ? block.timestamp - updatedAt_ : 0;
        if (age > _maxStalenessSeconds) {
            return (0, updatedAt_, false);
        }

        priceWad = _normalizePrice(answer, decimals);
        updatedAt = updatedAt_;
        valid = true;
    }

    function getNormalizedPrice(address feed) external view override returns (uint256) {
        IChainlinkAggregator(feed).latestRoundData();
        (uint256 priceWad, uint256 updatedAt, bool valid) = this.getPriceWithMetadata(feed);
        if (!valid) revert StalePrice(updatedAt, _maxStalenessSeconds);
        return priceWad;
    }

    /// @notice Returns TWAP for the given feed and window
    /// @dev MVP: returns current normalized spot price. Production will use historical rounds.
    function getTWAP(address feed, uint256 windowSeconds) external view override returns (uint256) {
        return this.getNormalizedPrice(feed);
    }

    function crossCheckOracles(address primaryFeed, address secondaryFeed) external view override returns (bool isValid, uint256 deviationBps) {
        (uint256 price1, , bool valid1) = this.getPriceWithMetadata(primaryFeed);
        if (!valid1) return (false, 10000);

        IPythPrice pyth = IPythPrice(secondaryFeed);
        (uint256 price2, , bool valid2) = pyth.getPrice();
        if (!valid2) return (false, 10000);

        if (price1 == 0 || price2 == 0) return (false, 10000);

        uint256 diff = (price1 > price2) ? price1 - price2 : price2 - price1;
        deviationBps = (diff * 10000) / price1;
        isValid = (deviationBps <= _maxOracleDeviationBps);
    }

    function maxStalenessSeconds() external view override returns (uint256) {
        return _maxStalenessSeconds;
    }

    function maxOracleDeviationBps() external view override returns (uint256) {
        return _maxOracleDeviationBps;
    }
}
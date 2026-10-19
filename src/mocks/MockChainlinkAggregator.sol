// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockChainlinkAggregator {
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint8 public _decimals;
    uint80 public roundId;
    uint80 public answeredInRound;

    constructor() {
        _decimals = 8;
    }

    function setLatestAnswer(int256 answer) external {
        latestAnswer = answer;
    }

    function setLatestTimestamp(uint256 timestamp) external {
        latestTimestamp = timestamp;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound_
        )
    {
        roundId_ = roundId;
        answer = latestAnswer;
        startedAt = latestTimestamp;
        updatedAt = latestTimestamp;
        answeredInRound_ = answeredInRound;
    }
}

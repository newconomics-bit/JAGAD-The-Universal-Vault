// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockPythPrice {
    uint256 public priceWad;
    uint256 public publishTime;
    bool public valid;

    function setPrice(uint256 price_) external {
        priceWad = price_;
    }

    function setPublishTime(uint256 time_) external {
        publishTime = time_;
    }

    function setValid(bool valid_) external {
        valid = valid_;
    }

    function getPrice() external view returns (uint256 priceWad_, uint256 publishTime_, bool valid_) {
        priceWad_ = priceWad;
        publishTime_ = publishTime;
        valid_ = valid;
    }
}

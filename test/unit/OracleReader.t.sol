// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OracleReader} from "../../src/OracleReader.sol";
import {MockChainlinkAggregator} from "../../src/mocks/MockChainlinkAggregator.sol";
import {MockPythPrice} from "../../src/mocks/MockPythPrice.sol";

contract OracleReaderTest is Test {
    OracleReader public reader;
    MockChainlinkAggregator public chainlink;
    MockPythPrice public pyth;
    address public owner = address(0x1234);
    address public notOwner = address(0x5678);

    uint256 constant MAX_STALENESS = 3600; // 1 hour
    uint256 constant MAX_DEVIATION_BPS = 500; // 5%
    uint256 constant BASE_TIMESTAMP = 1000000000;

    function setUp() public {
        vm.warp(BASE_TIMESTAMP);
        vm.prank(owner);
        reader = new OracleReader(MAX_STALENESS, MAX_DEVIATION_BPS);

        chainlink = new MockChainlinkAggregator();
        pyth = new MockPythPrice();

        // Setup Chainlink: price = 2000 * 10^8 (8 decimals), decimals = 8
        chainlink.setLatestAnswer(2000 * 10**8);
        chainlink.setLatestTimestamp(block.timestamp);
        chainlink.setDecimals(8);

        // Setup Pyth: price = 2000 * 10^18 (18 decimals WAD)
        pyth.setPrice(2000 * 10**18);
        pyth.setPublishTime(block.timestamp);
        pyth.setValid(true);

        // Link Pyth feed to Chainlink feed
        vm.prank(owner);
        reader.setPythFeed(address(chainlink), address(pyth));
    }

    function testGetNormalizedPriceSuccess() public {
        uint256 price = reader.getNormalizedPrice(address(chainlink));
        // Chainlink: 2000 * 10^8 with 8 decimals -> normalized to 18 decimals = 2000 * 10^18
        assertEq(price, 2000 * 10**18);
    }

    function testGetNormalizedPriceRevertsIfPriceZeroOrNegative() public {
        chainlink.setLatestAnswer(0);
        vm.expectRevert();
        reader.getNormalizedPrice(address(chainlink));

        chainlink.setLatestAnswer(-100);
        vm.expectRevert();
        reader.getNormalizedPrice(address(chainlink));
    }

    function testGetNormalizedPriceRevertsIfStale() public {
        // Set timestamp to maxStaleness + 1 seconds ago
        chainlink.setLatestTimestamp(BASE_TIMESTAMP - MAX_STALENESS - 1);
        vm.expectRevert();
        reader.getNormalizedPrice(address(chainlink));
    }

    function testGetPriceWithMetadataValid() public {
        (uint256 priceWad, uint256 updatedAt, bool valid) = reader.getPriceWithMetadata(address(chainlink));
        assertEq(priceWad, 2000 * 10**18);
        assertEq(updatedAt, block.timestamp);
        assertTrue(valid);
    }

    function testGetPriceWithMetadataInvalidWhenStale() public {
        chainlink.setLatestTimestamp(BASE_TIMESTAMP - MAX_STALENESS - 1);
        (uint256 priceWad, uint256 updatedAt, bool valid) = reader.getPriceWithMetadata(address(chainlink));
        assertEq(priceWad, 0);
        assertFalse(valid);
    }

    function testGetPriceWithMetadataInvalidWhenPriceZero() public {
        chainlink.setLatestAnswer(0);
        (uint256 priceWad, , bool valid) = reader.getPriceWithMetadata(address(chainlink));
        assertEq(priceWad, 0);
        assertFalse(valid);
    }

    function testCrossCheckOraclesValidWhenDeviationWithinThreshold() public {
        // Chainlink: 2000 * 10^18, Pyth: 2000 * 10^18 -> deviation = 0%
        (bool isValid, uint256 deviationBps) = reader.crossCheckOracles(address(chainlink), address(pyth));
        assertTrue(isValid);
        assertEq(deviationBps, 0);
    }

    function testCrossCheckOraclesInvalidWhenDeviationExceedsThreshold() public {
        // Chainlink: 2000 * 10^18, Pyth: 2110 * 10^18 -> deviation = 110 * 10000 / 2000 = 550 BPS (exceeds 500)
        pyth.setPrice(2110 * 10**18);
        (bool isValid, uint256 deviationBps) = reader.crossCheckOracles(address(chainlink), address(pyth));
        assertFalse(isValid);
        assertGt(deviationBps, MAX_DEVIATION_BPS);
    }

    function testCrossCheckOraclesReturnsFalseWhenPrimaryStale() public {
        chainlink.setLatestTimestamp(BASE_TIMESTAMP - MAX_STALENESS - 1);
        (bool isValid, uint256 deviationBps) = reader.crossCheckOracles(address(chainlink), address(pyth));
        assertFalse(isValid);
        assertEq(deviationBps, 10000);
    }

    function testCrossCheckOraclesReturnsFalseWhenSecondaryInvalid() public {
        pyth.setValid(false);
        (bool isValid, uint256 deviationBps) = reader.crossCheckOracles(address(chainlink), address(pyth));
        assertFalse(isValid);
        assertEq(deviationBps, 10000);
    }

    function testSetPythFeedOnlyOwner() public {
        MockChainlinkAggregator newChainlink = new MockChainlinkAggregator();
        MockPythPrice newPyth = new MockPythPrice();

        vm.prank(notOwner);
        vm.expectRevert();
        reader.setPythFeed(address(newChainlink), address(newPyth));

        vm.prank(owner);
        reader.setPythFeed(address(newChainlink), address(newPyth));
        assertEq(reader.pythFeedMapping(address(newChainlink)), address(newPyth));
    }

    function testMaxStalenessSeconds() public {
        assertEq(reader.maxStalenessSeconds(), MAX_STALENESS);
    }

    function testMaxOracleDeviationBps() public {
        assertEq(reader.maxOracleDeviationBps(), MAX_DEVIATION_BPS);
    }

    function testGetTWAPReturnsSpotPrice() public {
        uint256 twap = reader.getTWAP(address(chainlink), 300);
        assertEq(twap, 2000 * 10**18);
    }
}
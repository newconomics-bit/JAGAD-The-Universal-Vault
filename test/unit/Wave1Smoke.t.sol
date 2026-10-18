// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockChainlinkAggregator} from "../../src/mocks/MockChainlinkAggregator.sol";
import {MockPythPrice} from "../../src/mocks/MockPythPrice.sol";
import {MockDEXRouter} from "../../src/mocks/MockDEXRouter.sol";

contract Wave1Smoke is Test {
    MockERC20 public usdc;
    MockERC20 public paxg;
    MockERC20 public wbtc;
    MockChainlinkAggregator public chainlink;
    MockPythPrice public pyth;
    MockDEXRouter public dex;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        paxg = new MockERC20("PAXG", "PAXG", 18);
        wbtc = new MockERC20("WBTC", "WBTC", 8);
        chainlink = new MockChainlinkAggregator();
        pyth = new MockPythPrice();
        dex = new MockDEXRouter();
    }

    function testMockERC20MintAndBalance() public {
        usdc.mint(address(this), 1000);
        assertEq(usdc.balanceOf(address(this)), 1000);
    }

    function testMockERC20TransferAndApprove() public {
        usdc.mint(address(this), 1000);
        usdc.transfer(address(0x1234), 500);
        assertEq(usdc.balanceOf(address(this)), 500);
        assertEq(usdc.balanceOf(address(0x1234)), 500);

        usdc.approve(address(0x5678), 300);
        assertEq(usdc.allowance(address(this), address(0x5678)), 300);
    }

    function testChainlinkSetLatestAnswerAndRoundData() public {
        chainlink.setLatestAnswer(2000 * 10**8);
        chainlink.setLatestTimestamp(block.timestamp);
        (, int256 answer, , uint256 updatedAt, ) = chainlink.latestRoundData();
        assertEq(answer, 2000 * 10**8);
        assertEq(updatedAt, block.timestamp);
    }

    function testChainlinkStalePriceDetection() public {
        chainlink.setLatestAnswer(2000 * 10**8);
        uint256 oldTimestamp = 1000000000; // fixed timestamp
        chainlink.setLatestTimestamp(oldTimestamp);
        (, , , uint256 updatedAt, ) = chainlink.latestRoundData();
        assertEq(updatedAt, oldTimestamp);
    }

    function testPythSetPriceAndGetPrice() public {
        pyth.setPrice(2000 * 10**18);
        pyth.setPublishTime(block.timestamp);
        pyth.setValid(true);
        (uint256 price, uint256 time, bool valid) = pyth.getPrice();
        assertEq(price, 2000 * 10**18);
        assertEq(time, block.timestamp);
        assertTrue(valid);
    }

    function testDexRouterSetRateAndSwap() public {
        usdc.mint(address(this), 1000000);
        wbtc.mint(address(dex), 100000000);

        usdc.approve(address(dex), 1000000);
        dex.setRate(address(usdc), address(wbtc), 1e18);

        dex.swapExactTokensForTokens(1000000, address(usdc), address(wbtc), 0);
        assertEq(dex.lastTokenIn(), address(usdc));
        assertEq(dex.lastTokenOut(), address(wbtc));
        assertEq(dex.lastAmountIn(), 1000000);
        assertEq(dex.lastAmountOut(), 1000000);
    }

    function testDexRouterSwapRevertsMinAmountOutTooHigh() public {
        usdc.mint(address(this), 1000000);
        wbtc.mint(address(dex), 100000000);
        usdc.approve(address(dex), 1000000);
        dex.setRate(address(usdc), address(wbtc), 1e18);

        vm.expectRevert("min amount out too high");
        dex.swapExactTokensForTokens(1000000, address(usdc), address(wbtc), 2000000);
    }

    function testDexRouterSwapRevertsRateNotSet() public {
        usdc.mint(address(this), 1000000);
        usdc.approve(address(dex), 1000000);

        vm.expectRevert("rate not set");
        dex.swapExactTokensForTokens(1000000, address(usdc), address(wbtc), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./MockERC20.sol";

contract MockDEXRouter {
    mapping(address => mapping(address => uint256)) public rates;

    address public lastTokenIn;
    address public lastTokenOut;
    uint256 public lastAmountIn;
    uint256 public lastAmountOut;

    function setRate(address tokenIn, address tokenOut, uint256 rateWad) external {
        rates[tokenIn][tokenOut] = rateWad;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        uint256 rate = rates[tokenIn][tokenOut];
        if (rate == 0) {
            revert("rate not set");
        }

        amountOut = (amountIn * rate) / 1e18;
        if (amountOut < minAmountOut) {
            revert("min amount out too high");
        }

        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(tokenOut).transfer(msg.sender, amountOut);

        lastTokenIn = tokenIn;
        lastTokenOut = tokenOut;
        lastAmountIn = amountIn;
        lastAmountOut = amountOut;
    }
}

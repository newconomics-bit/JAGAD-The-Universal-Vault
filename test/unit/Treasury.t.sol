// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../../src/Treasury.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract TreasuryTest is Test {
    Treasury public treasury;
    MockERC20 public usdc;
    address public owner = address(0x1234);
    address public notOwner = address(0x5678);
    address public vault = address(0x9999);

    function setUp() public {
        vm.prank(owner);
        treasury = new Treasury();
        usdc = new MockERC20("USDC", "USDC", 6);
    }

    function testCollectFee() public {
        usdc.mint(vault, 1000);
        vm.prank(vault);
        usdc.approve(address(treasury), 500);

        vm.prank(vault);
        treasury.collectFee(address(usdc), 500);

        assertEq(usdc.balanceOf(address(treasury)), 500);
        assertEq(usdc.balanceOf(vault), 500);
    }

    function testWithdraw() public {
        usdc.mint(address(treasury), 1000);

        vm.prank(owner);
        treasury.withdraw(address(usdc), 300);

        assertEq(usdc.balanceOf(owner), 300);
        assertEq(usdc.balanceOf(address(treasury)), 700);
    }

    function testWithdrawRevertsNotOwner() public {
        usdc.mint(address(treasury), 1000);

        vm.prank(notOwner);
        vm.expectRevert();
        treasury.withdraw(address(usdc), 300);
    }

    function testSetGasReserve() public {
        vm.prank(owner);
        treasury.setGasReserve(address(usdc), 100);
        assertEq(treasury.gasReserve(address(usdc)), 100);
    }

    function testSetGasReserveRevertsNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        treasury.setGasReserve(address(usdc), 100);
    }
}
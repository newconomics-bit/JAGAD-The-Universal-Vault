// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {JagadToken} from "../../src/JagadToken.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract JagadTokenTest is Test {
    JagadToken public token;
    address public vault = address(0x1234);
    address public notVault = address(0x5678);

    function setUp() public {
        token = new JagadToken("JAGAD", "JAGAD", vault);
    }

    function testConstructor() public {
        assertEq(token.name(), "JAGAD");
        assertEq(token.symbol(), "JAGAD");
        assertEq(token.decimals(), 18);
        assertEq(token.vault(), vault);
    }

    function testConstructorRevertsZeroVault() public {
        vm.expectRevert();
        new JagadToken("JAGAD", "JAGAD", address(0));
    }

    function testMintSuccess() public {
        vm.prank(vault);
        token.mint(address(this), 1000);
        assertEq(token.balanceOf(address(this)), 1000);
        assertEq(token.totalSupply(), 1000);
    }

    function testMintRevertsNotVault() public {
        vm.prank(notVault);
        vm.expectRevert();
        token.mint(address(this), 1000);
    }

    function testBurnSuccess() public {
        vm.prank(vault);
        token.mint(address(this), 1000);
        assertEq(token.balanceOf(address(this)), 1000);

        vm.prank(vault);
        token.burn(address(this), 500);
        assertEq(token.balanceOf(address(this)), 500);
        assertEq(token.totalSupply(), 500);
    }

    function testBurnRevertsNotVault() public {
        vm.prank(vault);
        token.mint(address(this), 1000);

        vm.prank(notVault);
        vm.expectRevert();
        token.burn(address(this), 500);
    }

    function testBurnRevertsInsufficientBalance() public {
        vm.prank(vault);
        token.mint(address(this), 100);

        vm.prank(vault);
        vm.expectRevert(); // ERC20: burn amount exceeds balance
        token.burn(address(this), 500);
    }
}
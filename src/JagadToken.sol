// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IJagadToken} from "./interfaces/IJagadToken.sol";

error NotVault(address caller);

contract JagadToken is ERC20, IJagadToken {
    address public immutable vault_;

    constructor(string memory name_, string memory symbol_, address vaultAddr) ERC20(name_, symbol_) {
        if (vaultAddr == address(0)) revert NotVault(address(0));
        vault_ = vaultAddr;
    }

    modifier onlyVault() {
        if (msg.sender != vault_) revert NotVault(msg.sender);
        _;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }

    function vault() external view override returns (address) {
        return vault_;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UserToken is ERC20 {
    constructor()
        ERC20("UserToken", "UT")
    {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
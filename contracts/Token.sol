// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {

    constructor () ERC20("Vesting", "VTK") {
        _mint(msg.sender, 10000000 * (10 ** uint256(decimals())));
    }

}

// Contract address: 0x442cAA1d3A1184E451d2c80F8636F7aa3c0457C9
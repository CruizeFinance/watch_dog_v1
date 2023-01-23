// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICRERC20 {
    function mint(address, uint256) external;

    function burn(address, uint256) external;
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimal_
    ) external;

    function approve(address spender, uint256 amount) external returns (bool);
}

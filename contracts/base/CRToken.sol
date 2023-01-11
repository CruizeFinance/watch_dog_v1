// SPDX-License-Identifier: MI
pragma solidity =0.8.6;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract DAI is ERC20("DAI","DAI" ) {

    constructor(){
        _mint(msg.sender,1000 * 1e18);
    }
}
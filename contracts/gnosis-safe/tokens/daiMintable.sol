// SPDX-License-Identifier: MI
pragma solidity =0.8.18;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract daiMintable is ERC20("DAI","DAI") {

    constructor(
    ) {
    }
    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}
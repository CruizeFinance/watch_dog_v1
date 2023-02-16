// SPDX-License-Identifier: MI
pragma solidity =0.8.6;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract wethMintable is ERC20("Wrapped ETH","WETH") {

    constructor(
    ) {
    }
    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}
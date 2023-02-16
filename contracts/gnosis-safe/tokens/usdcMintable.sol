// SPDX-License-Identifier: MI
pragma solidity =0.8.6;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract usdcMintable is ERC20("USDC Coin","UDSC") {

    constructor(
    ) {
    }
    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}
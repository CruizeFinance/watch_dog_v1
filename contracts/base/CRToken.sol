
// / SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../libraries/Errors.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CRTokenUpgradeable is ERC20Upgradeable, OwnableUpgradeable {
    uint8 internal _decimal;

    /*
     * @notice   mint        will  ""mint"" CRtoken for the staker's.
     * @param      to_         address of the staker's.
     * @param     amount_      amount of token that staker's stake's.
     */

    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    /*
     * @notice   decimals       override the decimal function's
     * */

    function decimals() public view virtual override returns (uint8) {
        return _decimal;
    }

    /*
     * @notice initialize  will Call by the AssetPool contract while cloning the ERC20Upgradeable Contract.Will initialize the token symbol and name
     * @param    name_       name of the  ERC20Upgradeable Contract.
     * @param    symbol_     symbol of the  ERC20Upgradeable Contract.
     * @param    decimal_    decimal value of ERC20Upgradeable Contract.
     */

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimal_
    ) external initializer {
        if (bytes(name_).length == 0 ) revert EmptyName();
        if ( bytes(symbol_).length  == 0 ) revert EmptySymbol();
        if ( decimal_ ==  0) revert ZeroDecimal();
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        _decimal = decimal_;
    }

    /*
     * @notice      burn         Burn the cr tokens .
     * @param       account_          address of the staker's.
     * @param      amount_      amount of token that staker's stake's.
     */

    function burn(address account_, uint256 amount_) external onlyOwner {
        _burn(account_, amount_);
    }
}

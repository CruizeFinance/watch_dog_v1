// / SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "../libraries/Errors.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CRTokenUpgradeable is ERC20Upgradeable, OwnableUpgradeable {
    uint8 internal _decimal;

    /**
     * @notice mint will mint the cr token's
     * @param account_  address to mint token.
     * @param amount_ is the amount of `token` to mint.
     */
    function mint(address account_, uint256 amount_) external onlyOwner {
        _mint(account_, amount_);
    }

    /**
     * @notice  returns tokens decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimal;
    }

    /**
     * @notice Initializes the contract with immutable variables.
     * @param name_ is the token name.
     * @param symbol_ is the token symbol.
     * @param decimal_ is the token decimals.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimal_
    ) external initializer {
        if (bytes(name_).length == 0) revert EmptyName();
        if (bytes(symbol_).length == 0) revert EmptySymbol();
        if (decimal_ == 0) revert ZeroDecimal();
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        _decimal = decimal_;
    }

    /**
     * @notice burn will burn the cr token's
     * @param account_  address to burn token.
     * @param amount_ is the amount of `token` to burn.
     */
    function burn(address account_, uint256 amount_) external onlyOwner {
        _burn(account_, amount_);
    }
}

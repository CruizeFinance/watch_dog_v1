// SPDX-License-Identifier: MIT
import "../libraries/Errors.sol";
import "../storage/CruizeStorage.sol";
import "../base/getters/Getters.sol";
pragma solidity =0.8.6;

abstract contract Modifiers is CruizeStorage {
    /************************************************
     * MODIFIERS
     ***********************************************/
    /**
     * @dev Throws if called by any account other than the module.
     */
    modifier onlyModule(address _cruizeProxy) {
        if (msg.sender != _cruizeProxy)
            revert NotAuthorized(msg.sender, _cruizeProxy);
        _;
    }
    /**
     * @dev Throws if cruizeTokens mapping give's null.
     */
    modifier tokenIsAllowed(address token) {
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        _;
    }
    /**
     * @dev Throws if number is zero.
     */
    modifier numberIsNotZero(uint256 number) {
        if (number == 0) revert ZeroValue(number);
        _;
    }
    /**
     * @dev Throws if address is null.
     */
    modifier addressIsValid(address addr) {
        if (addr == address(0)) revert ZeroAddress(addr);
        _;
    }

    modifier isDisabled(address token) {
        if (isDisable[token]) revert DisabledAsset(token);
        _;
    }
    modifier checkVaultBalance(
        address token,
        uint256 totalTokenBalance,
        uint256 vaultTokenBalance
    ) {
        uint256 totalDeposit = vaults[token].lockedAmount +
            vaults[token].totalPending;
        if (totalTokenBalance == 0) {
            if (vaultTokenBalance < totalDeposit)
                revert VaultBalanceIsLessThenTheTotalDepsoit(
                    totalDeposit,
                    vaultTokenBalance
                );
        }
        if (totalTokenBalance > 0 && totalTokenBalance < totalDeposit) {
            revert VaultBalanceIsLessThenTheTotalDepsoit(
                totalDeposit,
                totalTokenBalance
            );
        }
        _;
    }
}

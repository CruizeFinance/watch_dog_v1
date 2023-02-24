// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "../../modifiers/Modifiers.sol";
import "../../module/ownable/OwnableUpgradeable.sol";
import "../../libraries/SharesMath.sol";
import "../../interfaces/ICRERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Getters is Modifiers, OwnableUpgradeable {
    using SafeMath for uint256;
    using ShareMath for Types.DepositReceipt;

    /************************************************
     *  GETTERS
     ***********************************************/
    /**
     * @notice Calculates the  management fee for this week's round.
     * @param token is the `asset` for which the fee will calculate.
     * @param currentBalance is total  value locked in valut.
     * @param pendingAmount is the pending deposit amount.
     * @param lastLockedAmount is the amount of funds locked from the previous round
     * @return vaultFee is the total vault Fee.
     */
    function getVaultFees(
        address token,
        uint256 currentBalance,
        uint256 pendingAmount,
        uint256 lastLockedAmount
    ) internal view returns (uint256 vaultFee) {
        uint256 lockedBalance = currentBalance > pendingAmount
            ? currentBalance.sub(pendingAmount)
            : 0;
        //slither-disable-next-line uninitialized-local
        uint256 _performanceFeeInAsset;
        //slither-disable-next-line uninitialized-local
        uint256 _managementFeeInAsset;
        uint256 decimal = 10 ** decimals(token);

        if (lockedBalance > lastLockedAmount) {
            // performance fee will be applied on round APY
            if (isPerformanceFeeEnabled) {
                _performanceFeeInAsset = performanceFee > 0
                    ? getPerformanceFee(
                        lockedBalance.sub(lastLockedAmount),
                        decimal
                    )
                    : 0;
            }

            // management fee will be applied on locked amount
            if (isManagementFeeEnable) {
                _managementFeeInAsset = managementFee > 0
                    ? getManagementFee(lockedBalance, decimal)
                    : 0;
            }
        }
        vaultFee = _performanceFeeInAsset.add(_managementFeeInAsset);
    }

    /**
     * @notice Getter for returning the account's share balance split between account and vault holdings
     * @param account is the account to lookup share balance for.
     * @param token is the `asset` address for which shares are calculating.
     * @return heldByAccount is the shares held by account.
     * @return heldByVault is the shares held on the vault (unredeemedShares).
     */
    function shareBalances(
        address token,
        address account
    )
        public
        view
        tokenIsAllowed(token)
        addressIsValid(account)
        returns (
            uint256 heldByAccount,
            uint256 heldByVault,
            uint256 totalShares
        )
    {
        Types.DepositReceipt memory depositReceipt = depositReceipts[account][
            token
        ];

        if (depositReceipt.round < ShareMath.PLACEHOLDER_UINT) {
            return (balanceOf(token, account), 0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            vaults[token].round,
            priceOfRound(token, depositReceipt.round),
            decimals(token)
        );
        return (
            balanceOf(token, account),
            unredeemedShares,
            balanceOf(token, account).add(unredeemedShares)
        );
    }

    /*
     * @notice Returns the user total locked amount in the strategy
     * @params token asset address
     * @params account user address
     */
    function balanceOfUser(
        address token,
        address account
    )
        public
        view
        tokenIsAllowed(token)
        addressIsValid(account)
        returns (uint256 balance)
    {
        Types.DepositReceipt memory depositReceipt = depositReceipts[account][
            token
        ];
        Types.VaultState memory vaultState = vaults[token];
        uint16 currentRound = vaultState.round;
        uint256 decimal = decimals(token);

        // calculate total unredeemed shares of user's
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt( // 0
            currentRound,
            priceOfRound(token, depositReceipt.round),
            decimal
        );

        uint256 currentAmount = ShareMath.sharesToAsset(
            unredeemedShares,
            priceOfRound(token, currentRound - 1),
            decimal
        );
        return balance.add(currentAmount);
    }

    /**
     * @notice Returns the vault's total balance, including the amounts locked into a strategy.
     * @return total balance of the vault, including the amounts locked in strategy.
     */
    function totalBalance(address token) internal view returns (uint256) {
        if (token == ETH) return gnosisSafe.balance;
        else return IERC20(token).balanceOf(gnosisSafe);
    }

    /**
     * @notice Returns the `asset` total supply.
     * @return total supply of the asset.
     */
    function totalSupply(address token) internal view returns (uint256) {
        return IERC20(cruizeTokens[token]).totalSupply();
    }

    /**
     * @notice Returns the cr`token` balance.
     */
    function balanceOf(
        address token,
        address account
    )
        public
        view
        tokenIsAllowed(token)
        addressIsValid(account)
        returns (uint256)
    {
        return IERC20(cruizeTokens[token]).balanceOf(account);
    }

    /**
     * @notice Returns the vault round price per shares.
     */
    function priceOfRound(
        address token,
        uint16 round
    ) private view returns (uint256) {
        if (roundPricePerShare[token][round] == 0) return 1e18;
        return roundPricePerShare[token][round];
    }

    /**
     * @notice Returns the vault managementFee.
     */
    function getManagementFee(
        uint256 totalBalanceLocked,
        uint256 decimal
    ) public view returns (uint256) {
        return calculateFee(totalBalanceLocked, decimal, managementFee);
    }

    /**
     * @notice Returns the vault performanceFee.
     */
    function getPerformanceFee(
        uint256 roundAPY,
        uint256 decimal
    ) public view returns (uint256) {
        return calculateFee(roundAPY, decimal, performanceFee);
    }

    /**
     * @notice Returns the fee.
     * @param amount is on which fee calculated.
     * @param decimal is token decimal.
     * @param feePercent is the parcentage of fee to charge.
     */
    function calculateFee(
        uint256 amount,
        uint256 decimal,
        uint256 feePercent
    ) internal pure returns (uint256 feeInAsset) {
        feeInAsset = feePercent
            .mul(decimal)
            .mul(amount)
            .div(FEE_MULTIPLIER)
            .div(100 * decimal);
    }

    function pricePerShare(address token) external view returns (uint256) {
        return
            ShareMath.pricePerShare(
                totalSupply(token),
                totalBalance(token),
                vaults[token].totalPending,
                decimals(token)
            );
    }

    /**
     * @notice Returns the vault feeRecipient.
     */
    function getFeeRecipient() external view onlyOwner returns (address) {
        return feeRecipient;
    }

    /**
     * @notice Returns the vault total pending.
     */
    function totalTokenPending(
        address token
    ) external view tokenIsAllowed(token) returns (uint256) {
        return vaults[token].totalPending;
    }

    /**
     * @notice Returns the token decimals.
     */

    function decimals(address _token) internal view returns (uint256 decimal) {
        if (_token == ETH) decimal = 18;
        else decimal = ICRERC20(_token).decimals();
    }
}

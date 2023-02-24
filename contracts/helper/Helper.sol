// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../module/zodiac/contracts/interfaces/IAvatar.sol";
import "../libraries/Types.sol";
import "../libraries/SharesMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../storage/CruizeStorage.sol";
import "../base/getters/Getters.sol";
contract Helper is CruizeStorage,Getters {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @notice Redeems shares that are owned to the account.
     * @param _token is the address of withdrawal `asset`.
     */
    function _redeemShares(
        address _token,
        Types.DepositReceipt memory depositReceipt,
        uint256 numShares,
        uint256 unredeemedShares,
        uint16 currentRound
    ) internal {
        // If we have a depositReceipt on the same round, BUT we have some unredeemed shares.
        // we debit from the unredeemedShares, but leave the amount field intact.
        // If the round has past, with no new deposits, we just zero it out for new deposits.
        if (depositReceipt.round < currentRound) {
            depositReceipts[msg.sender][_token].amount = 0;
        }
        ShareMath.assertUint128(numShares);
        depositReceipts[msg.sender][_token].unredeemedShares = uint128(
            unredeemedShares.sub(numShares)
        );

        IERC20(cruizeTokens[_token]).safeTransfer(msg.sender, numShares);
    }

    /**
     * @notice Helper function to make delegatecall on gnosis safe to transfer either an
     * ETH transfer or ERC20 transfer.
     * @param _token  withdrawal `asset` address.
     * @param _receiver is the receiving address.
     * @param _amount the transfer amount.
     */
    function _transferHelper(
        address _token,
        address _receiver,
        uint256 _amount
    ) internal {
        bytes memory _data = abi.encodeWithSignature(
            "transferFromSafe(address,address,address,uint256)",
            _token,
            _receiver,
            cruizeProxy,
            _amount
        );

        require(
            IAvatar(gnosisSafe).execTransactionFromModule(
                module,
                0,
                _data,
                Enum.Operation.DelegateCall
            ),
            "failed to transfer funds"
        );
    }
        /**
     * @notice Calculate the shares to mint, new price per share, and amount of funds to re-allocate as collateral for the new round
     * @param _token  `asset` address.
     *  @param params is the  parameters passed to compute the next round state.
     * @return newLockedAmount is the amount of funds to allocate for the new round.
     * @return queuedWithdrawAmount is the amount of funds set aside for withdrawal.
     * @return newPricePerShare is the price per share of the new round.
     * @return mintShares is the amount of shares to mint from deposits.
     * @return totalVaultFee is the total amount of fee charged by vault.
     */
    function calculateSharePrice(
        address _token,
        Types.CloseParams memory params
    )
        internal
        view
        returns (
            uint256 newLockedAmount,
            uint256 queuedWithdrawAmount,
            uint256 newPricePerShare,
            uint256 mintShares,
            uint256 totalVaultFee
        )
    {
        Types.VaultState memory vaultState = vaults[_token];
        uint256 currentBalance = params.totalBalance;
        uint256 pendingAmount = vaultState.totalPending;
        uint256 lastLockedAmount = vaultState.lockedAmount;

        // Total amount of queued withdrawal shares from previous rounds (doesn't include the current round)
        uint256 lastQueuedWithdrawShares = vaultState.queuedWithdrawShares;

        (totalVaultFee) = getVaultFees(
            _token,
            // we don't charge fee on lastQueuedWithdrawAmount
            currentBalance.sub(params.lastQueuedWithdrawAmount),
            pendingAmount,
            lastLockedAmount
        );

        // Take into account the fee
        // so we can calculate the newPricePerShare
        currentBalance = currentBalance.sub(totalVaultFee);
        {
            newPricePerShare = ShareMath.pricePerShare(
                params.currentShareSupply.sub(lastQueuedWithdrawShares),
                currentBalance.sub(params.lastQueuedWithdrawAmount),
                pendingAmount,
                params.decimals
            );
            queuedWithdrawAmount = params.lastQueuedWithdrawAmount.add(
                ShareMath.sharesToAsset(
                    params.currentQueuedWithdrawShares,
                    newPricePerShare,
                    params.decimals
                )
            );
            // After closing the short, if the options expire in-the-money
            // vault pricePerShare would go down because vault's asset balance decreased.
            // This ensures that the newly-minted shares do not take on the loss.
            mintShares = ShareMath.assetToShares(
                pendingAmount,
                newPricePerShare,
                params.decimals
            );
        }
        return (
            currentBalance.sub(queuedWithdrawAmount), // new locked balance subtracts the queued withdrawals
            queuedWithdrawAmount,
            newPricePerShare,
            mintShares,
            totalVaultFee
        );
    }
}

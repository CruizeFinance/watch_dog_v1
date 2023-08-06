// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;
import "./getters/Getters.sol";
import "../helper/Helper.sol";
import "./setters/Setters.sol";
import "../interfaces/ICRERC20.sol";
import "../libraries/SharesMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../module/zodiac/contracts/core/Module.sol";
import "../module/pausable/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../module/reentrancyGuard/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
abstract contract CruizeVault is
    Setters,
    Helper,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    Module
{
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeMath for uint128;
    using ShareMath for Types.DepositReceipt;
    using SafeERC20 for IERC20;

    receive() external payable {
        revert();
    }

    function _updateDepositInfo(address _token, uint256 _amount) internal {
        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;
        uint256 decimal = decimalsOf(_token);

        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        // If we have an unprocessed pending deposit from the previous rounds, we have to process it.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            decimal
        );

        uint256 depositAmount = _amount;
        // If we have a pending deposit in the current round, we add on to the pending deposit.
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(_amount);
            depositAmount = newAmount;
        }
        uint256 totalDeposit = uint256(depositReceipt.totalDeposit).add(
            _amount
        );
        depositReceipts[msg.sender][_token] = Types.DepositReceipt({
            round: currentRound,
            amount: uint104(depositAmount),
            unredeemedShares: uint128(unredeemedShares),
            totalDeposit: uint104(totalDeposit)
        });

        uint256 newTotalPending = uint256(vaultState.totalPending).add(_amount);
        ShareMath.assertUint128(newTotalPending);

        vaultState.totalPending = uint128(newTotalPending);
    }

    /**
     *
     * @notice Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`.
     * @param _amount is the amount to withdraw.
     * @param _token withdrawal token address.
     */
    function _instantWithdrawal(address _token, uint104 _amount) internal {
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;
        uint16 depositRound = depositReceipt.round;
        if (depositRound != currentRound)
            revert InvalidWithdrawalRound(depositRound, currentRound);
        uint256 receiptAmount = depositReceipt.amount;
        if (_amount > receiptAmount)
            revert NotEnoughWithdrawalBalance(receiptAmount, _amount);
        ShareMath.assertUint104(_amount);

        depositReceipt.amount = uint104(receiptAmount.sub(_amount));
        depositReceipt.totalDeposit = depositReceipt.totalDeposit - _amount;
        vaultState.totalPending = uint128(
            uint256(vaultState.totalPending).sub(_amount)
        );
        _transferHelper(_token, msg.sender, uint256(_amount));
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes.
     * @param _shares is the number of shares to withdraw.
     * @param _token is the address of withdrawal `asset`.
     */
    function _initiateStandardWithdrawal(
        address _token,
        uint256 _shares
    ) internal {
        uint16 currentRound = vaults[_token].round;
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            decimalsOf(_token)
        );
        // If we have a pending deposit in the current round.
        // We do a max redeem before initiating a withdrawal.
        // But we check if they must first have unredeemed shares.
        if (_shares > unredeemedShares)
            revert NotEnoughWithdrawalShare(unredeemedShares, _shares);

        if (depositReceipt.amount > 0 || depositReceipt.unredeemedShares > 0) {
            _redeemShares(
                _token,
                depositReceipt,
                _shares,
                unredeemedShares,
                currentRound
            );
        }
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        bool withdrawalIsSameRound = withdrawal.round == currentRound;
        uint256 existingShares = uint256(withdrawal.shares);
        uint256 withdrawalShares;
        if (withdrawalIsSameRound) {
            withdrawalShares = existingShares.add(_shares);
        } else {
            if (existingShares > 0)
                revert WithdrawalAlreadyExists(existingShares);
            withdrawalShares = _shares;
            withdrawal.round = currentRound;
        }

        ShareMath.assertUint128(withdrawalShares);
        withdrawal.shares = uint128(withdrawalShares);

        currentQueuedWithdrawalShares[_token] = uint256(
            currentQueuedWithdrawalShares[_token]
        ).add(_shares).toUint128();
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round.
     * @param _token withdrawal token address.
     */
    function _completeStandardWithdrawal(address _token) internal {
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint256 withdrawalShares = withdrawal.shares;
        uint16 withdrawalRound = withdrawal.round;
        uint256 decimal = decimalsOf(_token);
        uint16 currentRound = vaults[_token].round;

        if (withdrawalShares == 0) revert ZeroWithdrawalShare();
        if (withdrawalRound == currentRound)
            revert InvalidWithdrawalRound(withdrawalRound, currentRound);

        withdrawal.shares = 0;
        vaultState.queuedWithdrawShares = uint128(
            uint256(vaultState.queuedWithdrawShares).sub(withdrawalShares)
        );
        uint256 withdrawAmount = ShareMath.sharesToAsset(
            withdrawalShares,
            roundPricePerShare[_token][withdrawalRound],
            decimal
        );
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        ShareMath.assertUint104(withdrawAmount);

        if (withdrawAmount > depositReceipt.totalDeposit) {
            depositReceipt.totalDeposit = 0;
        } else {
            depositReceipt.totalDeposit =
                depositReceipt.totalDeposit -
                uint104(withdrawAmount);
        }

        lastQueuedWithdrawAmounts[_token] = lastQueuedWithdrawAmounts[_token]
            .sub(withdrawAmount);
        ICRERC20(cruizeTokens[_token]).burn(msg.sender, withdrawalShares);
        _transferHelper(_token, msg.sender, uint256(withdrawAmount));
        emit StandardWithdrawal(msg.sender,withdrawAmount,_token);
    }

    /************************************************
     *  VAULT OPERATIONS
     ***********************************************/

    /**
     * @notice Helper function that performs most administrative tasks
     * such as setting next strategy, minting new shares, getting vault fees, etc.
     * @param lastQueuedWithdrawAmount is old queued withdraw amount.
     * @param currentQueuedWithdrawShares is the queued withdraw shares for the current round.
     * @param token  is the `asset` for which round will close.
     * @return lockedBalance is the new balance used to calculate next strategy purchase size or collateral size
     * @return queuedWithdrawAmount is the new queued withdraw amount for this round.
     */
    function _closeRound(
        address token,
        uint256 lastQueuedWithdrawAmount,
        uint256 currentQueuedWithdrawShares,
        uint256 totalTokenBalance
    ) internal returns (uint256 lockedBalance, uint256 queuedWithdrawAmount) {
        uint256 mintShares;
        uint256 totalVaultFee;
        Types.VaultState storage vaultState = vaults[token];

        uint256 newPricePerShare;
        (
            lockedBalance,
            queuedWithdrawAmount,
            newPricePerShare,
            mintShares,
            totalVaultFee
        ) = calculateSharePrice(
            token,
            Types.CloseParams(
                decimalsOf(token),
                totalBalance(token,totalTokenBalance),
                totalSupply(token),
                lastQueuedWithdrawAmount,
                currentQueuedWithdrawShares
            )
        );

        // Finalize the pricePerShare at the end of the round
        uint16 currentRound = vaultState.round;
        roundPricePerShare[token][currentRound] = newPricePerShare;
        vaultState.totalPending = 0;
        vaultState.round = uint16(currentRound + 1);
        roundPricePerShare[token][vaultState.round] = 1e18;
        ICRERC20(cruizeTokens[token]).mint(address(this), mintShares);
        if (totalVaultFee > 0) {
            _transferHelper(token, payable(feeRecipient), totalVaultFee);
            emit CollectVaultFee(token, totalVaultFee);
        }
        emit CloseRound(token, currentRound, newPricePerShare, lockedBalance);
        return (lockedBalance, queuedWithdrawAmount);
    }

    /**
     * @notice Main function to make delegatecall on Gnosis Safe to transfer either an
     * ETH transfer or ERC20 transfer.
     * @param _paymentToken withdrawal token address.
     * @param _receiver is the receiving address.
     * @param _amount the transfer amount
     */
    function transferFromSafe(
        address _paymentToken,
        address _receiver,
        uint256 _amount
    )
        external
        addressIsValid(_paymentToken)
        addressIsValid(_receiver)
        nonReentrant
    {
        // Only delegate call would be accepted from a contract
         if(msg.sig == this.transferFromSafe.selector && msg.data.length > 0 && Address.isContract(msg.sender)){
             if (_paymentToken == ETH) {
            (bool sent, ) = _receiver.call{value: _amount}("");
            if (!sent) revert FailedToTransferETH();
        } else {
            IERC20(_paymentToken).safeTransfer(_receiver, _amount);
        }
        emit TransferFromSafe(_receiver, _amount,_paymentToken);
         }
         else {
            revert NotAuthorized(msg.sender,address(this));
         }
    }
}

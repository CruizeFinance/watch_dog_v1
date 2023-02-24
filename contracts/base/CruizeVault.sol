// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "../libraries/Types.sol";
import "../storage/CruizeStorage.sol";
import "../libraries/SharesMath.sol";
import "../interfaces/ICRERC20.sol";
// before
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
// after
import "../module/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../module/reentrancyGuard/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";
import "../libraries/Events.sol";
import "../modifiers/Modifiers.sol";
import "./getters";
import "./setters";

abstract contract CruizeVault is
    CruizeStorage,
    Module,
    ReentrancyGuardUpgradeable,
    Modifiers,
    Getters,
    Setters
{
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeMath for uint128;
    using ShareMath for Types.DepositReceipt;
    using SafeERC20 for IERC20;

    receive() external payable {
        revert();
    }

    /************************************************
     *  DEPOSIT & WITHDRAWALS
     ***********************************************/

    /**
     * @notice  Deposits the `asset` from msg.sender.
     * @param _amount user depositing amount.
     */
    function _depositETH(uint256 _amount) internal {
        if (gnosisSafe.balance.add(_amount) > vaults[ETH].cap)
            revert VaultReachedDepositLimit(vaults[ETH].cap);
        _updateDepositInfo(ETH, _amount);
        // transfer token to gnosis valut.
        (bool sent, ) = gnosisSafe.call{value: _amount}("");
        if (!sent) revert FailedToTransferETH();
    }

    /**
     * @notice Deposits the `asset` from msg.sender
     * @param _token depositing token address.
     * @param _amount is the amount of `asset` to deposit.
     */
    function _depositERC20(address _token, uint256 _amount) internal {
        if (
            IERC20(_token).balanceOf(gnosisSafe).add(_amount) >
            vaults[_token].cap
        ) revert VaultReachedDepositLimit(vaults[_token].cap);
        _updateDepositInfo(_token, _amount);
        // transfer token to gnosis vault.
        IERC20(_token).safeTransferFrom(msg.sender, gnosisSafe, _amount);
    }

    /**
     * @notice Deposits the `asset` from msg.sender added to `msg.sender`'s deposi receipts.
     * @notice Used for vault -> vault deposits on the user's behalf.
     * @param _amount is the amount of `asset` to deposit.
     * @param _token  is the deposits `asset` address.
     */
    function _updateDepositInfo(address _token, uint256 _amount) private {
        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;
        uint256 decimal = decimals(_token);

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
        emit Events.Deposit(msg.sender, _amount, _token);
    }

    /**
     *
     * @notice Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`.
     * @param _amount is the amount to withdraw.
     * @param _token withdrawal token address.
     */
    function _instantWithdrawal(
        address _token,
        uint104 _amount
    ) internal tokenIsAllowed(_token) numberIsNotZero(_amount) {
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

        emit Events.InstantWithdrawal(
            msg.sender,
            _amount,
            currentRound,
            _token
        );
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes.
     * @param _shares is the number of shares to withdraw.
     * @param _token is the address of withdrawal `asset`.
     */
    function _initiateStandardWithdrawal(
        address _token,
        uint256 _shares
    ) internal tokenIsAllowed(_token) numberIsNotZero(_shares) {
        uint16 currentRound = vaults[_token].round;
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            decimals(_token)
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

        emit Events.InitiateStandardWithdrawal(msg.sender, _token, _shares);
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round.
     * @param _token withdrawal token address.
     */
    function _completeStandardWithdrawal(
        address _token
    ) internal tokenIsAllowed(_token) {
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint256 withdrawalShares = withdrawal.shares;
        uint16 withdrawalRound = withdrawal.round;
        uint256 decimal = decimals(_token);
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
        _transferHelper(_token, msg.sender, withdrawAmount);
        emit Events.StandardWithdrawal(msg.sender, withdrawAmount, _token);
    }

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

    /************************************************
     *  VAULT OPERATIONS
     ***********************************************/
    /**
     * @notice Helper function that helps to save gas for writing values into the roundPricePerShare map.
     *         Writing `1` into the map makes subsequent writes warm, reducing the gas from 20k to 5k.
     *         Having 1 initialized beforehand will not be an issue as long as we round down share calculations to 0.
     * @param numRounds is the number of rounds to initialize in the map.
     */
    function initRounds(
        address token,
        uint256 numRounds
    )
        external
        tokenIsAllowed(token)
        numberIsNotZero(numRounds)
        onlyOwner
        nonReentrant
    {
        uint16 _round = vaults[token].round;

        for (uint16 i = 0; i < numRounds; ) {
            uint16 index = _round + i;
            require(roundPricePerShare[token][index] == 0, "Initialized");
            roundPricePerShare[token][index] = Types.PLACEHOLDER_UINT;
            unchecked {
                i++;
            }
        }
    }

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
        uint256 currentQueuedWithdrawShares
    )
        internal
        tokenIsAllowed(token)
        returns (uint256 lockedBalance, uint256 queuedWithdrawAmount)
    {
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
                decimals(token),
                totalBalance(token),
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

        ICRERC20(cruizeTokens[token]).mint(address(this), mintShares);
        if (totalVaultFee > 0) {
            _transferHelper(token, payable(feeRecipient), totalVaultFee);
            emit Events.CollectVaultFee(token, totalVaultFee);
        }
        emit Events.CloseRound(
            token,
            currentRound,
            newPricePerShare,
            lockedBalance
        );
        return (lockedBalance, queuedWithdrawAmount);
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
    ) private {
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

    // CruizeProxy -> cruizeModuleLogic -> gProxyAddress -> GnosisSafe(DELEGATE) -> transferFromSafe
    //

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
        address cruizeProxy,
        uint256 _amount
    ) external onlyModule(cruizeProxy) nonReentrant {
        if (_paymentToken == ETH) {
            (bool sent, ) = _receiver.call{value: _amount}("");
            if (!sent) revert FailedToTransferETH();
            return;
        }

        IERC20(_paymentToken).safeTransfer(_receiver, _amount);
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
        private
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

// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

library Types {
    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/
    uint256 internal constant UNIT = 10**18;
    uint256 internal constant PLACEHOLDER_UINT = 1;

    struct VaultState {
        // 32 byte slot 1
        // Current round number. `round` represents the number of `period`s elapsed.
        uint16 round;
        // Amount that is currently locked for selling options
        uint104 lockedAmount;
        uint128 totalPending;
        // Total amount of queued withdrawal shares from previous rounds (doesn't include the current round)
        uint128 queuedWithdrawShares;
        //  Total amount that can be held in a vault.
        uint104 cap;
    }

    struct DepositReceipt {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Deposit amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        uint104 amount;
        // Unredeemed shares balance
        uint128 unredeemedShares;
        //  total locked amount.
        uint104 totalDeposit;

    }

    struct Withdrawal {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Number of shares withdrawn
        uint128 shares;
    }

    struct CloseParams {
        // Decimals of  token
        uint256 decimals;
        // Total balance of token.
        uint256 totalBalance;
        //  Total share supply for an round.
        uint256 currentShareSupply;
        //  Total queued withdrawal from the last round.
        uint256 lastQueuedWithdrawAmount;
        //  Total  current round queued withdrawal.
        uint256 currentQueuedWithdrawShares;
    }
}

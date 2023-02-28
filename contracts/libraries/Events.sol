// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Events {
    /************************************************
     *  EVENTS
     ***********************************************/
    event CreateToken(
        address indexed token,
        address indexed crToken,
        string tokenName,
        string tokenSymbol,
        uint8 decimal,
        uint256 tokenCap
    );
    event Deposit(
        address indexed token,
        address indexed account,
        uint256 amount
    );
    event StandardWithdrawal(
        address indexed token,
        address indexed account,
        uint256 amount
    );
    event InstantWithdrawal(
        address indexed token,
        address indexed account,
        uint256 amount,
        uint16 currentRound
    );
    event InitiateStandardWithdrawal(
        address indexed token,
        address indexed account,
        uint256 shares
    );
    event CloseRound(
        address indexed token,
        uint16 indexed round,
        uint256 SharePerUnit,
        uint256 lockedAmount
    );
    event TransferFromSafe(
        address indexed token,
        address indexed account,
        uint256 amount
    );
    event ManagementFeeSet(uint256 managementFee, uint256 newManagementFee);
    event CapSet(address indexed token, uint256 oldCap, uint256 newCap);
    event PerformanceFeeSet(uint256 performanceFee, uint256 newPerformanceFee);
    event CollectVaultFee(address indexed token, uint256 vaultFee);
    event ChangeAssetStatus(address indexed token, bool status);
   event deListToken(address indexed token);
}

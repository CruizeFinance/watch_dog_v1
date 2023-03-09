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
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event StandardWithdrawal(
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event InstantWithdrawal(
        address indexed account,
        uint256 amount,
        uint16 currentRound,
        address indexed token
    );
    event InitiateStandardWithdrawal(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event CloseRound(
        address indexed token,
        uint16 indexed round,
        uint256 SharePerUnit,
        uint256 lockedAmount
    );
    event TransferFromSafe(
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event ManagementFeeSet(uint256 managementFee, uint256 newManagementFee);
    event CapSet(address indexed token, uint256 oldCap, uint256 newCap);
    event PerformanceFeeSet(uint256 performanceFee, uint256 newPerformanceFee);
    event CollectVaultFee(address indexed token, uint256 vaultFee);
    event ChangeAssetStatus(address indexed token, bool status);
   event deListToken(address indexed token);
}

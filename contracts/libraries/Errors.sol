// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
error ZeroAddress(address ZeroAddress);
error DisabledAsset(address AssetDisabled);
error AssetNotAllowed(address AssetNotAllowed);
error WithdrawalAlreadyExists(uint256 WithdrawalAlreadyExists);
error AssetAlreadyExists(address AssetAlreadyExists);
error ZeroAmount(uint256 ZeroAmount);
error EmptyName();
error ZeroValue(uint256 ZeroValue);
error EmptySymbol();
error ZeroDecimal();
error InvalidWithdrawalRound(
    uint256 WithdrawalRequestRound,
    uint256 currentRound
);
error InvalidInitiateStandardWithdrawalRound(
    uint256 depositRound,
    uint256 currentRound
);
error NotEnoughWithdrawalBalance(
    uint256 withdrawalBalance,
    uint256 withdrawalRequestBalance
);
error ZeroWithdrawalShare(

);
error NotEnoughWithdrawalShare(
    uint256 withdrawalshare,
    uint256 withdrawalRequestshare
);
error NotAuthorized(address actualAddr, address ownerAddr);
error InvalidAassetPerShare();
error InvalidFee();
error FailedToTransferETH();
error VaultReachedDepositLimit(uint256 limit);
error InvalidVaultAddress(address invalidVaultAddress);

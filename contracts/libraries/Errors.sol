// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
error ZeroAddress(address ZeroAddress);
error AssetNotAllowed(address AssetNotAllowed);
error WithdrawalAlreadyExists(uint256 WithdrawalAlreadyExists);
error AssetAlreadyExists(address AssetAlreadyExists);
error ZeroAmount(uint256 ZeroAmount);
error EmptyName();
error EmptySymbol();
error ZeroDecimal();
error InvalidWithdrawalRound(
    uint256 WithdrawalRequestRound,
    uint256 currentRound
);
error InvalidinitiateStandardWithdrawalRound(
    uint256 depositRound,
    uint256 currentRound
);
error NotEnoughWithdrawalBalance(
    uint256 withdrawalBalance,
    uint256 withdrawalRequestBalance
);
error TokenReachedDepositLimit(uint256 limit);
error InvalidVaultAddress(address invalidVaultAddress);

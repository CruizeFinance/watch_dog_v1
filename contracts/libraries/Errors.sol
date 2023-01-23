// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/** 
  * Custom Error events
  */
  error ZeroAddress(address ZeroAddress);
  error AssetNotAllowed(address AssetNotAllowed);
  error WithdrawalAlreadyExists(uint256 WithdrawalAlreadyExists );
  error AssetAlreadyExists (address AssetAlreadyExists);
  error ZeroAmount(uint256 ZeroAmount);
  error EmptyName();
  error EmptySymbol();
  error ZeroDecimal();
  error InvalidWithdrawalRound(uint256 depositRoundOrWithdrawalRequestRound,uint256 currentRound);
 error NotEnoughWithdrawalBalance(uint256 withdrawalBalance,uint256 withdrawalRequestBalance);
 error InvalidVaultAddress(address invalidVaultAddress);


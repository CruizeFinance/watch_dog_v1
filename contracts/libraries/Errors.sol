pragma solidity ^0.8.0;

/** 
  * Error events
  */
  error ZeroAddress(address ZeroAddress);
  error AssetNotAllowed(address AssetNotAllowed);
  error AssetAlreadyExists(address AssetAlreadyExists );
  error ZeroAmount(uint256 ZeroAmount);
  error EmptyName();
  error EmptySymbol();
  error ZeroDecimal();
  error InvalidRound(uint256 round);
  error NotEnoughBalance(uint256 balance);
 error NotEnoughWithdrawalBalance(uint256 balance);


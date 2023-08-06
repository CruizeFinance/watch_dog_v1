// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
error ZeroAddress(address ZeroAddress);
error DisabledAsset(address AssetDisabled);
error AssetNotAllowed(address AssetNotAllowed);
error WithdrawalAlreadyExists(uint256 WithdrawalAlreadyExists);
error AssetAlreadyExists(address AssetAlreadyExists);
error ZeroAmount(uint256 ZeroAmount);
error EmptyName();
error ShouldBeSame();
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
error ZeroWithdrawalShare();
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
error VaultBalanceIsLessThenTheTotalDeposit(
    uint256 TotalDeposit,
    uint256 vaultTotalBalance
);
error TotalBalanceIsLessThenTheTotalDeposit(
     uint256 TotalDeposit,
    uint256 TotalBalance
);
error InvalidLength(uint256 tokenAddressArray, uint256 tokenBalanceArray);
error InvalidCap(uint256 VaultBalance, uint256 newCap);
error TokenBalanceShouldBeZero(uint256 tokenBalance);

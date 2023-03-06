// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
interface ICamelotMaster {

  function grailToken() external view returns (address);
  function yieldBooster() external view returns (address);

  function getPoolInfo(address _poolAddress) external view returns (address poolAddress, uint256 allocPoint, uint256 lastRewardTime, uint256 reserve, uint256 poolEmissionRate);

  function claimRewards() external returns (uint256);
}
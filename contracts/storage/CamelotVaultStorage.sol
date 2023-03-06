// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "../libraries/Types.sol";

abstract contract CamelotVaultStorage {
    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/

    // Info of each NFT (staked position).
    struct StakingPosition {
        uint256 amount; // How many lp tokens the user has provided
        uint256 amountWithMultiplier; // Amount + lock bonus faked amount (amount + amount*multiplier)
        uint256 startLockTime; // The time at which the user made his deposit
        uint256 lockDuration; // The lock duration in seconds
        uint256 lockMultiplier; // Active lock multiplier (times 1e2)
        uint256 rewardDebt; // Reward debt
        uint256 boostPoints; // Allocated xGRAIL from yieldboost contract (optional)
        uint256 totalMultiplier; // lockMultiplier + allocated xGRAIL boostPoints multiplier
        uint256 pendingXGrailRewards; // Not harvested xGrail rewards
        uint256 pendingGrailRewards; // Not harvested Grail rewards
    }
    
// we might use multiple pool's 
    uint256 public vaultTokenId; // This tokenId will represent the whole position in camelot staking pool
    // user => nftInfo
    mapping(uint256 => StakingPosition) public stakingInfo;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __camelotVault_gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INftPool {
    /**
     * @dev Returns general "pool" info for this contract
     */
    function getPoolInfo() external view;
    /**
     * @dev Returns master contract address . 
     */
    function  master()  external returns (address);
        
    
    /**
     * @dev Returns a position info
     */
    function getStakingPosition(uint256 tokenId)
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );

    /**
     * @dev Returns pending rewards for a position
     */
    function pendingRewards(uint256 tokenId) external view returns (uint256);

    function createPosition(uint256 amount, uint256 lockDuration) external;
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Add to an existing staking position
     *
     * Can only be called by spNFT's owner or operators
     */
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPosition(uint256 tokenId) external;

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     * spNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external;

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw)
        external;

    /**
     * @dev Split a staking position into two
     *
     * Can only be called by nft's owner
     */
    function splitPosition(uint256 tokenId, uint256 splitAmount) external;

    /**
     * @dev Merge an array of staking positions into a single one with "lockDuration"
     * Can't be used on positions with a higher lock duration than "lockDuration" param
     *
     * Can only be called by spNFT's owner
     */
    function mergePositions(uint256[] calldata tokenIds, uint256 lockDuration)
        external;
}

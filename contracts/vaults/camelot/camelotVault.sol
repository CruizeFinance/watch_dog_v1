// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "./crERC721.sol";
import "../../interfaces/INftPool.sol";
import "../../storage/CamelotVaultStorage.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CamelotVault is CamelotVaultStorage, crERC721 {
    using SafeMath for uint256;

    INftPool public TrustedNftPool =
        INftPool(0x6BC938abA940fB828D39Daa23A94dfc522120C11);

    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _url
    ) public virtual override initializer {
        __ERC721PresetMinterPauserAutoId_init(_name, _symbol, _url);
    }

    function deposit(uint256 tokenId) external {
        uint256 amountToAdd;
        TrustedNftPool.transferFrom(msg.sender, address(this), tokenId); // fetch the user nft to the contract.
        TrustedNftPool.harvestPositionTo(tokenId, msg.sender); // send pending rewards to the user.
        // Mint NFT to the use for his position in our cruize camelot vault.
        uint256 mintedTokenId = mint(msg.sender);
        {
            (
                uint256 amount,
                uint256 amountWithMultiplier,
                uint256 startLockTime,
                uint256 lockDuration,
                uint256 lockMultiplier,
                uint256 rewardDebt,
                uint256 boostPoints,
                uint256 totalMultiplier
            ) = TrustedNftPool.getStakingPosition(tokenId);
            amountToAdd = amount;
            uint256 pendingRewards = TrustedNftPool.pendingRewards(tokenId);
            // save user staking info for later use in withdrawal
            stakingInfo[mintedTokenId] = StakingPosition({
                amount: amount,
                amountWithMultiplier: amountWithMultiplier,
                startLockTime: startLockTime,
                lockDuration: lockDuration,
                lockMultiplier: lockMultiplier,
                rewardDebt: rewardDebt,
                boostPoints: boostPoints,
                totalMultiplier: totalMultiplier,
                pendingXGrailRewards: 0, // TODO: need to be calculate
                pendingGrailRewards: pendingRewards // TODO: need to be calculate
            });

            TrustedNftPool.withdrawFromPosition(tokenId, amount); // withdraw user all LPs tokens
        }

        (uint256 amount, , , , , , , ) = TrustedNftPool.getStakingPosition(
            vaultTokenId
        ); // fetch the contract staking info from camelot pool
        if (amount > 0) {
            // if cruize camelotVault has already depsited amount in camelote
            // staking pool then simply increase the stakign amount
            TrustedNftPool.addToPosition(vaultTokenId, amountToAdd);
        } else {
            TrustedNftPool.createPosition(amountToAdd, 0);
        }
    }

    function withdraw(uint256 tokenId) external {
        //Step-01 first burn the crNFT from user wallet
        burn(tokenId);

        // Step-02 fetch user staking info
        StakingPosition memory userInfo = crStakingPositionInfo(tokenId);

        // Step-03 split/createPosition the position
        /// TODO: need to take care of user rewards during staking in our cruize vault
        TrustedNftPool.createPosition(userInfo.amount, lockDuration);
        
        // Step-04 Calculate user rewards
        // Step-05 Send user rewards in the form of grails tokens
    }


    function crStakingPositionInfo(uint256 tokenId) public view returns(StakingPosition memory){
        return stakingInfo[tokenId];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "./crERC721.sol";
import "../../interfaces/INftPool.sol";
import "../../interfaces/ICamelotRouter.sol";
import "../../interfaces/ICamelotMaster.sol";
import "../../storage/CamelotVaultStorage.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

contract CamelotVault is CamelotVaultStorage, crERC721 {
    using SafeMath for uint256;
    address constant NFTPOOL = 0x6BC938abA940fB828D39Daa23A94dfc522120C11;
    INftPool public TrustedNftPool = INftPool(NFTPOOL);
    ICamelotRouter public router =
        ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    event CreatePosition(
        uint256 indexed tokenId,
        uint256 amount,
        uint256 lockDuration
    );
    event Deposit(
        address indexed account,
        uint256 tokenId,
        uint256 mintedTokenId,
        uint256 lpTokens
    );

    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _url
    ) public virtual override initializer {
        __ERC721PresetMinterPauserAutoId_init(_name, _symbol, _url);
    }

    function deposit(uint256 tokenId) external {
        uint256 amountToAdd;
        (address lp,uint256 accRewardsPerShare , ) = poolInfo();
        TrustedNftPool.transferFrom(msg.sender, address(this), tokenId); // fetch the user nft to the contract.
        TrustedNftPool.harvestPosition(tokenId); // send pending rewards to the user.
        // Mint NFT to the use for his position in our cruize camelot vault.
        uint256 mintedTokenId = mint(msg.sender);
        {
            (
                uint256 amount,
                ,
                ,
                uint256 lockDuration,
                ,
                ,
                ,
                
            ) = TrustedNftPool.getStakingPosition(tokenId);
            amountToAdd = amount;

             // calculate bonuses
            uint256 lockMultiplier = TrustedNftPool.getMultiplierByLockDuration(0);
            uint256 amountWithMultiplier = amountToAdd.mul(lockMultiplier.add(1e4)).div(1e4);

            // save user staking info for later use in withdrawal
            stakingInfo[mintedTokenId] = StakingPosition({
                amount: amount,
                amountWithMultiplier: amountWithMultiplier,
                startLockTime: _currentBlockTimestamp(),
                lockDuration: lockDuration,
                lockMultiplier: lockMultiplier,
                rewardDebt: amountWithMultiplier.mul(accRewardsPerShare).div(1e18),
                boostPoints: 0,
                totalMultiplier: lockMultiplier
            });

            TrustedNftPool.withdrawFromPosition(tokenId, amount); // withdraw user all LPs tokens
        }

        (uint256 amount, , , , , , , ) = TrustedNftPool.getStakingPosition(
            vaultTokenId
        ); // fetch the contract staking info from camelot pool
        
        IERC20(lp).approve(NFTPOOL, amountToAdd);
        if (amount > 0) {
            // if cruize camelotVault has already depsited amount in camelot
            // staking pool then simply increase the stakign amount
            TrustedNftPool.addToPosition(vaultTokenId, amountToAdd);
        } else {
            IERC20(lp).approve(NFTPOOL, amountToAdd);
            TrustedNftPool.createPosition(amountToAdd, 0);
        }

        emit Deposit(msg.sender, tokenId, mintedTokenId, amountToAdd);
    }

    function withdraw(uint256 tokenId) external {
        //Step-01 first burn the crNFT from user wallet
        burn(tokenId);

        // Step - 02  withdraw a postion and get LP token's
        TrustedNftPool.withdrawFromPosition(vaultTokenId, userInfo.amount);

        // Step-02 fetch user staking info
        StakingPosition memory userInfo = crStakingPositionInfo(tokenId);
        uint256 userReward = pendingRewards(tokenId);


        // Step-03 Send user rewards in the form of grails tokens
        TrustedNftPool.harvestPosition(vaultTokenId);
        console.log("userReward:", userReward);
        address master = TrustedNftPool.master();
        address grailToken = ICamelotMaster(master).grailToken();
        console.log(
            "grailsToken:",
            IERC20(grailToken).balanceOf(address(this))
        );
        IERC20(grailToken).transfer(msg.sender, userReward);

        // Step-05 approve & createPosition the position
        // (bool success0, bytes memory data0) = grailToken.delegatecall(
        //     abi.encodeWithSignature(
        //         "approve(address,uint256)",
        //         NFTPOOL,
        //         type(uint256).max
        //     )
        // );
        // (bool success, bytes memory data) = NFTPOOL.delegatecall(
        //     abi.encodeWithSignature(
        //         "createPosition(uint256,uint256)",
        //         userInfo.amount,
        //         0
        //     )
        // );
        // require(success0 && success);
    }

    function crStakingPositionInfo(uint256 tokenId)
        public
        view
        returns (StakingPosition memory)
    {
        return stakingInfo[tokenId];
    }

    /**
     * @dev Returns pending rewards for a position
     */
    function pendingRewards(uint256 tokenId)
        internal
        view
        returns (uint256 rewards)
    {
        StakingPosition memory position = stakingInfo[tokenId];
        (
            ,
            uint256 accRewardsPerShare,
            uint256 lpSupplyWithMultiplier
        ) = poolInfo();

        (
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 poolEmissionRate
        ) = masterInfo();

        // recompute accRewardsPerShare if not up to date
        if (
            (reserve > 0 || _currentBlockTimestamp() > lastRewardTime) &&
            lpSupplyWithMultiplier > 0
        ) {
            uint256 duration = _currentBlockTimestamp().sub(lastRewardTime);
            // adding reserve here in case master has been synced but not the pool
            uint256 tokenRewards = duration.mul(poolEmissionRate).add(reserve);
            accRewardsPerShare = accRewardsPerShare.add(
                tokenRewards.mul(1e18).div(lpSupplyWithMultiplier)
            );
        }
        console.log("amountWithMultiplier:",position.amountWithMultiplier);
        console.log("accRewardsPerShare:",accRewardsPerShare);
        console.log("rewardDebt:",position.rewardDebt);
        return
            position.amountWithMultiplier.mul(accRewardsPerShare).div(1e18).sub(
                position.rewardDebt
            );
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }

    function poolInfo()
        internal
        view
        returns (
            address lp,
            uint256 accRewardsPerShare,
            uint256 lpSupplyWithMultiplier
        )
    {
        (
            lp,
            ,
            ,
            ,
            accRewardsPerShare,
            ,
            lpSupplyWithMultiplier,

        ) = TrustedNftPool.getPoolInfo();
    }

    function masterInfo()
        internal
        view
        returns (
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 poolEmissionRate
        )
    {
        address master = TrustedNftPool.master();
        (, , lastRewardTime, reserve, poolEmissionRate) = ICamelotMaster(master)
            .getPoolInfo(NFTPOOL);
    }

    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 grailAmount,
        uint256 xGrailAmount
    ) external returns (bool) {
        return true;
    }

    function onNFTAddToPosition(
        address operator,
        uint256 tokenId,
        uint256 lpAmount
    ) external returns (bool) {
        return true;
    }

    function onNFTWithdraw(
        address operator,
        uint256 tokenId,
        uint256 lpAmount
    ) external returns (bool) {
        return true;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        if (vaultTokenId == 0) vaultTokenId = tokenId;
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}

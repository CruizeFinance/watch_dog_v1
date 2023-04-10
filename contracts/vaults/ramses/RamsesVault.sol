// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

import "../../storage/RamsesVaultStorage.sol";
import "../../module/ownable/OwnableUpgradeable.sol";
import "../../module/pausable/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../module/reentrancyGuard/ReentrancyGuardUpgradeable.sol";

import "hardhat/console.sol";

// weth 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
// usdc 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
// ram  0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418
// vrAMM-WETH/USDC 0x5513a48F3692Df1d9C793eeaB1349146B2140386
// router 0xaaa87963efeb6f7e0a2711f397663105acb1805e
// voter 0xAAA2564DEb34763E3d05162ed3f5C2658691f499 (for claiming fees)
// weth/usdc voting pool 0x5513a48F3692Df1d9C793eeaB1349146B2140386
// Gauge 0xDBA865F11bb0a9Cd803574eDd782d8B26Ee65767
// votingEscrow 0xAAA343032aA79eE9a6897Dab03bef967c3289a06
// minter 0xAAAA0b6BaefaeC478eB2d1337435623500AD4594

// addLiquidity[router] -> LP-Tokens -> DepositAll( lps )[Gauge] => getReward() [Gauge] -> RAM Tokens

// => Lock RAM-Tokens [votingEscrow] => veNFT => vote [Voter] => ClaimFee[Voter]

// TODO: check either we can withdraw LP if we go into locking state.

// [1-6] -> [1-6]-> claim fee-> MM
// deposit -> addLiquidity -> getLPs -> depositLp[Gauge] -> getReward[Gauge]
// -> RAM Tokens -> Lock RAM-Tokens[VotingEscrow] -> veNFT -> vote[Voter]

// -> withdraw -> getReward[Gauge] -> updateUserRewards -> removeLiquidity -> Transfer RAM to user

// -> claimFees -> claimFees[Voter] -> transfer Fee to Cruize Wallet

contract RamsesVault is
    RamsesVaultStorage,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 totalRamLocked;

    error LENGTH_NOT_EQUAL();
    error ROUND_EXPIRED();
    error NOT_ACTIVE();

    event Deposit(uint256 amount0,uint256 amount1,uint256 liquidity);
    event Withdraw(uint256 amount0,uint256 amount1,uint256 liquidity,uint256 reward);

    function initialize(
        address _token0,
        address _token1,
        bool _stable,
        address _feeRecipient
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        address pairToken = RAMSES_ROUTER.pairFor(_token0, _token1, _stable);
        lp = IPair(pairToken);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        stable = _stable;
        feeRecipient = _feeRecipient;

        // round = Round({round: 1, status: Status.ACTIVE});
    }

    modifier isActive() {
        if (round.status != Status.ACTIVE) revert NOT_ACTIVE();
        _;
    }
    function deposit(uint256 amount0, uint256 amount1) external nonReentrant {
        
        uint256 liquidity  =_addLiquidity(amount0,amount1);
        Deposits memory deposit = deposits[msg.sender];
        deposit.amount0 += amount0;
        deposit.amount1 += amount1;
        deposit.liquidity += liquidity;
        deposit.onlyLiquidity= false;
        deposits[msg.sender] = deposit;

        _deposit(liquidity);
        emit Deposit(amount0,amount1,liquidity);
    }

    function depositLP(uint256 liquidity) external nonReentrant {
        lp.transferFrom(msg.sender,address(this),liquidity);
        _deposit(liquidity);
    }

    function withdraw() external nonReentrant {
        address account = msg.sender;
        Deposits memory deposit = deposits[account];
        _claimRamTokens();
        RAMSES_GAUGE.withdraw(deposit.liquidity);
        updateRewardPerToken(account);
        uint256 amount0;
        uint256 amount1;
        if(deposit.onlyLiquidity){
            lp.transfer(account,deposit.liquidity);
        }
        else{
            lp.approve(address(RAMSES_ROUTER),deposit.liquidity);
            ( amount0, amount1)=_removeLiquidity(account);
        }

        uint256 _reward = storedRewardsPerUser[account];
        if (_reward > 0 && RAM_TOKEN.balanceOf(address(this)) >= _reward) {
            storedRewardsPerUser[account] = 0;
            RAM_TOKEN.transfer(account,Math.min(_reward,RAM_TOKEN.balanceOf(address(this))));
        }
        derivedBalances[account] = derivedBalance(account);
        emit Withdraw(amount0,amount1, deposit.liquidity,_reward);

        delete deposits[account];
    }

     function closeRound() external onlyOwner {
        // round.status = Status.END;

        // address[] memory tokens = new address[](1);
        // tokens[0] = address(RAM_TOKEN);
        // claim RAM tokens
        // _claimRamTokens();
        // withdraw all lp tokens
        // RAMSES_GAUGE.withdrawAll();
        // reset vote
        // RAMSES_VOTER.reset(tokenId); // active period = 1680739200 + 1week = 1681344000
                                                                        //   1681427833
        // withdraw all RAM tokens
        // RAMSES_VOTING_ESCROW.withdraw(tokenId);
        // console.log(RAM_TOKEN.balanceOf(address(this)));
        // console.log(totalRamLocked);
        // claimFees();
        // lockAndVote();
    }

    function _deposit(uint256 liquidity) internal {
        lp.approve(address(RAMSES_GAUGE), liquidity);
        RAMSES_GAUGE.depositAll(tokenId);
        updateRewardPerToken(msg.sender);
        derivedBalances[msg.sender] = derivedBalance(msg.sender);
        // if (RAMSES_GAUGE.earned(address(RAM_TOKEN), address(this)) > 0)
        //     claimRewards();
    }

    function _claimRewards() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(RAM_TOKEN);
        // claim RAM tokens
        RAMSES_GAUGE.getReward(address(this), tokens);
        // approve RAM tokens to the voting escrow contract
        RAM_TOKEN.approve(
            address(RAMSES_VOTING_ESCROW),
            RAM_TOKEN.balanceOf(address(this))
        );

        // If our escrow locking period has been expired then we simply withdraw our all RAM tokens
        // and create a new lock for all RAM tokens
        if (
            tokenId != 0 &&
            RAMSES_VOTING_ESCROW.locked__end(tokenId) < block.timestamp
        ) revert ROUND_EXPIRED();

        // After claiming RAM tokens we can create lock to get the veNFT for voting
        if (tokenId == 0) {
            lockAndVote();
        } else if (RAMSES_VOTING_ESCROW.locked__end(tokenId) > block.timestamp){
            totalRamLocked += RAM_TOKEN.balanceOf(address(this));
            RAMSES_VOTING_ESCROW.increase_amount(
                tokenId,
                RAM_TOKEN.balanceOf(address(this))
            );
        }
    }

    function _addLiquidity(uint256 amount0, uint256 amount1) internal returns(uint256 liquidity) {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        token0.approve(address(RAMSES_ROUTER), amount0);
        token1.approve(address(RAMSES_ROUTER), amount1);
        (, , liquidity) = RAMSES_ROUTER.addLiquidity(
            address(token0),
            address(token1),
            stable,
            amount0,
            amount1,
            0,
            0,
            address(this),
            block.timestamp + 600
        );
    }

    function _removeLiquidity(address _account) internal returns(uint256 amount0,uint256 amount1) {
        Deposits memory deposit = deposits[_account];
        
        (amount0,amount1) = RAMSES_ROUTER.removeLiquidity(
            address(token0),
            address(token1),
            stable,
            deposit.liquidity,
            0,
            0,
            _account,
            block.timestamp + 600
        );
    }

    function _claimRamTokens() internal {
         address[] memory tokens = new address[](1);
        tokens[0] = address(RAM_TOKEN);
        // claim RAM tokens
        RAMSES_GAUGE.getReward(address(this), tokens);
    }

    function lockAndVote() internal {
        // creating lock for RAM tokens and get the veNFT tokenId
        totalRamLocked += RAM_TOKEN.balanceOf(address(this));
        tokenId = RAMSES_VOTING_ESCROW.create_lock(
            RAM_TOKEN.balanceOf(address(this)),
            MAX_LOCK
        );

        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        // POOL will be the weth/usdc voting pool for which we use veNFT to vote.
        pools[0] = POOL;
        /// @TODO: we have to determine the weight for vote.
        weights[0] = RAMSES_VOTER.weights(POOL);
        // vote the veNFT to the give pool
        RAMSES_VOTER.vote(tokenId, pools, weights);
    }

    function earned(
        address account
    ) internal view returns (uint256) {
        return
            (derivedBalances[account] *
                (RAMSES_GAUGE.rewardPerToken(address(RAM_TOKEN)) -
                    userRewardPerTokenStored[account])) /
            PRECISION +
            storedRewardsPerUser[account];
    }

    function updateRewardPerToken( address account) internal {
        derivedSupply = RAMSES_GAUGE.derivedSupply();
        rewardPerTokenStored = RAMSES_GAUGE.rewardPerToken(address(RAM_TOKEN));
        storedRewardsPerUser[account] = earned( account);
        userRewardPerTokenStored[account] = rewardPerTokenStored;
    }

     function derivedBalance(address account) internal view returns (uint256) {
        uint256 _balance = deposits[account].liquidity;
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = 0;
        return Math.min((_derived + _adjusted), _balance);
    }

    function claimFees() public {
        address[] memory feeDistributer = new address[](1);
        feeDistributer[0] = RAMSES_VOTER.feeDistributers(address(RAMSES_GAUGE));
        
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](4);

        tokens[0][0] = address(token0);
        tokens[0][1] = address(token1);
        tokens[0][2] = address(RAM_TOKEN);


        RAMSES_VOTER.claimFees(feeDistributer, tokens, tokenId);
        // transfer claimed fee to fee recipient
        token0.transfer(feeRecipient, token0.balanceOf(address(this)));
        token1.transfer(feeRecipient, token1.balanceOf(address(this)));
        RAM_TOKEN.transfer(feeRecipient, RAM_TOKEN.balanceOf(address(this)));
    }

    function pendingRewardsFromGuage() public view returns(uint256) {
        return RAMSES_GAUGE.earned(address(RAM_TOKEN),address(this));
    }
}

/*
active_period = ap
week-1 = w1
week-2 = w2
week-3 = w3
week-4 = w4
deposit = d
lock ram = lck

            t1                      t2                      t3                      t4                      t5                      t6
            ap
            r#1                    r#2
            |-----------------------|------------------------|-----------------------|-----------------------|-----------------------|
d1                    100lp         |
lck-t3      |------1000 RAM --------|------------------------|
                                closeRound
                                claimFees
                                  lck-t2
d2                                  |--------80 lp-----------|
lck-t4                              |--------8000 RAM--------|-----------------------|
                                startRound               closeRound
                                                         claimFees
                                                            lck-


nft#1

we can only set lock time to next nearest week its because of ramses smart contract.
another problem with locking we can only withdraw our locked ram tokens after one week of active period which is defined in ramses minter contract.
*/
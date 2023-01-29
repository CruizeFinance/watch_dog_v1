// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "hardhat/console.sol";
import "./base/CruizeVault.sol";
import "./base/Proxy.sol";

contract Cruize is CruizeVault, Proxy {
    using SafeMath for uint256;

    constructor(
        address _owner,
        address _vault,
        address _crContract,
        uint256 _managementFee
    ) CruizeVault(_owner, _vault, _crContract, _managementFee) {}

    /**
     * @notice createToken will Clone CRTokenUpgradeable (ERC20 token).
     * @param name name of ERC20Upgradeable Contract.
     * @param symbol symbol of ERC20Upgradeable Contract.
     * @param decimal decimal value of ERC20Upgradeable Contract.
     */

    function createToken(
        string memory name,
        string memory symbol,
        address token,
        uint8 decimal,
        uint104 tokencap
    ) external onlyOwner {
        if (cruizeTokens[token] != address(0)) revert AssetAlreadyExists(token);
        ICRERC20 crToken = ICRERC20(createClone(crContract));
        cruizeTokens[token] = address(crToken);
        crToken.initialize(name, symbol, decimal);
        vaults[token].round = 1;
        vaults[token].cap = tokencap;
        emit CreateToken(address(crToken), name, symbol, decimal);
    }

    /**
     * @notice This function will be use for depositing assets.
     * @param token depositing token address.
     * @param amount user depositing amount.
     */
    function deposit(address token, uint256 amount)
        external
        payable
        nonReentrant
    {
        if (token == ETH) {
            _depositETH(msg.value);
        } else {
            _depositERC20(token, amount);
        }
    }

    /**
     * @notice This function will be use for depositing assets.
     * @param token depositing token address.
     */
    function withdraw(address token) external nonReentrant {
        _completeStandardWithdrawal(token);
    }

    /**
     * @notice This function will be use for initiating withdrawal request
     * before the round closing.
     * @param amount withdrawal amount.
     * @param token depositing token address.
     */
    function initiateWithdrawal(uint256 amount, address token)
        external
        nonReentrant
    {
        _initiateStandardWithdrawal(amount, token);
    }

    /**
     * @notice This function will be use for instant withdraws.
     * @param amount user withdrawal amount.
     * @param token withdrawal token address.
     */
    function withdrawInstantly(uint104 amount, address token)
        external
        nonReentrant
    {
        _withdrawInstantly(amount, token);
    }

    /**
     * @notice function closeRound  will be responsible for closing current round.
     * @param token token address.
     */
    function closeRound(address token) external nonReentrant onlyOwner {
        if (token == address(0)) revert ZeroAddress(token);
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        uint256 currQueuedWithdrawShares = currentQueuedWithdrawalShares[token];
        (uint256 lockedBalance, uint256 queuedWithdrawAmount) = _closeRound(
            token,
            uint256(lastQueuedWithdrawAmounts[token]),
            currQueuedWithdrawShares
        );

        lastQueuedWithdrawAmounts[token] = queuedWithdrawAmount;
        Types.VaultState storage vaultState = vaults[token];
        uint256 newQueuedWithdrawShares = uint256(
            vaultState.queuedWithdrawShares
        ).add(currQueuedWithdrawShares);
        ShareMath.assertUint128(newQueuedWithdrawShares);
        vaultState.queuedWithdrawShares = uint128(newQueuedWithdrawShares);

        currentQueuedWithdrawalShares[token] = 0;

        ShareMath.assertUint104(lockedBalance);
        vaultState.lockedAmount = uint104(lockedBalance);
    }
}

/**

r#1 { vault:{round:1,eth:10 ,lockedAmount:0,lastLockedAmount:0,totalPending:10,queuedWithdrawShares:0} user1:{receipt:{round:1,amount:10,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1, mintedShares:10 } INITIAL
r#1 { vault:{round:1,eth:10 ,lockedAmount:10,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user1:{receipt:{round:1,amount:10,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1, mintedShares:10 } AFTER-CLOSE

20% APY
r#2 { vault:{round:2,eth:10 ,lockedAmount:10,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user1:{receipt:{round:1,amount:10,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1, mintedShares:10 } INITIAL    
r#2 { vault:{round:2,eth:20 ,lockedAmount:10,lastLockedAmount:0,totalPending:10,queuedWithdrawShares:0} user1:{receipt:{round:2,amount:10,unredeemedShares:10}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1, mintedShares:10 } DEPOSIT
r#2 { vault:{round:2,eth:22 ,lockedAmount:22,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user1:{receipt:{round:2,amount:10,unredeemedShares:10}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1.2, mintedShares:18.33 } AFTER-CLOSE

50% APY
r#3 { vault:{round:3,eth:22 ,lockedAmount:22,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user2:{receipt:{round:3,amount:0,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:0, mintedShares:18.33 }INITIAL
r#3 { vault:{round:3,eth:32 ,lockedAmount:22,lastLockedAmount:0,totalPending:10,queuedWithdrawShares:0} user2:{receipt:{round:3,amount:10,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:0, mintedShares:18.33 } DEPOSIT  10 ETH
r#3 { vault:{round:3,eth:32+(11apy)= 43 ,lockedAmount:22,lastLockedAmount:0,totalPending:10,queuedWithdrawShares:0} user2:{receipt:{round:3,amount:10,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1.8, mintedShares: 23.89 } AFTER -CLOSE

10% APY
r#4 { vault:{round:4,eth:43 ,lockedAmount:43,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user1:{receipt:{round:4,amount:0,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:0, mintedShares:23.89 }INITIAL 10+1
r#4 { vault:{round:4,eth:47.3 ,lockedAmount:43,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user1:{receipt:{round:4,amount:0,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:1.9799, mintedShares: 23.89  } AFTER-CLOSE

10% APY
r#5 { vault:{round:5,eth:47.3 ,lockedAmount:47.3,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user2:{receipt:{round:4,amount:0,unredeemedShares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:0,pricePerShare:0, mintedShares:23.89 }INITIAL
r#5 { vault:{round:5,eth:47.3 ,lockedAmount:47.3,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user2:{withdraw:{round:4,shares:5.56}}, currentQueuedWithdrawShares:5.56,lastQueuedWithdrawAmount:0,pricePerShare:0, mintedShares:23.89 }INITIATE-WITHDRAW
r#5 { vault:{round:5,eth:52.03 ,lockedAmount:47.3,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:0} user2:{withdraw:{round:4,shares:5.56}}, currentQueuedWithdrawShares:5.56,lastQueuedWithdrawAmount:0,pricePerShare:2.1778, mintedShares:23.89 }AFTER-CLOSE 11+1.1=> -12.1
r#5 { vault:{round:5,eth:52.03 ,lockedAmount:39.93,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:5.56} user2:{withdraw:{round:4,shares:5.56}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:12.1,pricePerShare:2.1778, mintedShares:23.89 }AFTER-CLOSE 11+1.1=> -12.1

0% APY
r#6 { vault:{round:6,eth:52.03 ,lockedAmount:39.93,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:5.56} user1:{withdraw:{round:6,shares:0}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:12.1,pricePerShare:0, mintedShares:23.89 }INITIAL
r#6 { vault:{round:6,eth:52.03 ,lockedAmount:39.93,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:5.56} user1:{withdraw:{round:6,shares:18.33}}, currentQueuedWithdrawShares:18.33,lastQueuedWithdrawAmount:12.1,pricePerShare:0, mintedShares:23.89 }INITIATE-WITHDRAW
r#6 { vault:{round:6,eth:52.03 ,lockedAmount:0,lastLockedAmount:0,totalPending:0,queuedWithdrawShares:5.56+18.33} user1:{withdraw:{round:6,shares:18.33}}, currentQueuedWithdrawShares:0,lastQueuedWithdrawAmount:  52.02,pricePerShare:2.1783, mintedShares:23.89 }AFTER-CLOSE

 USER-1
 R2 = ( 10 + 2 ) 
    = 12
    = 12 + 10 = 22
R3  = 22 + 11 = 33
R4  = 33 + 3.3 = 36.3
R5  = 36.3 + 3.63
R5  =   39.93

USER-1

12.1

TOTAL = 39.93 + 12.1  = 52.03

*/

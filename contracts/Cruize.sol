// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "hardhat/console.sol";
import "./base/CruizeVault.sol";
import "./base/Proxy.sol";

contract Cruize is CruizeVault, Proxy {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /************************************************
     *  CONSTRUCTOR & INITIALIZATION
     ***********************************************/

    constructor(
        address _owner,
        address _vault,
        address _crContract,
        uint256 _managementFee,
        uint _performanceFee
    )
        CruizeVault(
            _owner,
            _vault,
            _crContract,
            _managementFee,
            _performanceFee
        )
    {}

    /**
     * @notice createToken will Clone CRTokenUpgradeable (ERC20 token).
     * @param name name of crtoken  .
     * @param symbol symbol of crtoken .
     * @param decimal decimal value of crtoken.
     */
    function createToken(
        string memory name,
        string memory symbol,
        address token,
        uint8 decimal,
        uint104 tokenCap
    ) external numberIsNotZero(tokenCap) onlyOwner {
        if (cruizeTokens[token] != address(0)) revert AssetAlreadyExists(token);
        ICRERC20 crToken = ICRERC20(createClone(crContract));
        cruizeTokens[token] = address(crToken);
        crToken.initialize(name, symbol, decimal);
        vaults[token].round = 1;
        vaults[token].cap = tokenCap;
        emit CreateToken(token,address(crToken), name, symbol, decimal, tokenCap);
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
        isDisabled(token)
    {
        if (token == ETH) {
            _depositETH(msg.value);
        } else {
            _depositERC20(token, amount);
        }
    }

    /************************************************
     *  VAULT OPERATIONS
     ***********************************************/
    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     * @param token depositing token address.
     */
    function standardWithdrawal(address token) external nonReentrant isDisabled(token) {
        _completeStandardWithdrawal(token);
    }

    /**

     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param numShares is the number of shares to withdraw
     * @param token withdrawal `asset` address.
     */
    function initiateWithdrawal(address token, uint256 numShares)
        external
        nonReentrant
        isDisabled(token)
    {
        _initiateStandardWithdrawal(token, numShares);
    }

    /**
     * @notice Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`
     * @param amount is the amount to withdraw.
     * @param token withdrawal `asset` address.
     */
    function instantWithdrawal(address token, uint256 amount)
        external
        nonReentrant
        isDisabled(token)
    {
        ShareMath.assertUint104(amount);
        _instantWithdrawal(token, amount.toUint104());
    }

    /**
     * @notice function closeRound  will be responsible for closing current round.
     * @param token token address.
     */
    function closeRound(address token) external nonReentrant onlyOwner {
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
        //slither-disable-next-line reentrancy-no-eth
        currentQueuedWithdrawalShares[token] = 0;

        ShareMath.assertUint104(lockedBalance);
        vaultState.lockedAmount = uint104(lockedBalance);
    }
}

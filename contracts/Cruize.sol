// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "hardhat/console.sol";
import "./base/CruizeVault.sol";
import "./base/Proxy.sol";

contract Cruize is CruizeVault, Proxy {
    using SafeMath for uint256;
    using SafeCast for uint256;


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
    function standardWithdraw(address token) external nonReentrant {
        _completeStandardWithdrawal(token);
    }

    /**
     * @notice This function will be use for initiating withdrawal request
     * before the round closing.
     * @param amount withdrawal amount.
     * @param token depositing token address.
     */
    function initiateWithdrawal(address token , uint256 amount)
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
    function instantWithdraw(address token , uint256 amount)
        external
        nonReentrant
    {
        _instantWithdraw(amount.toUint104(), token);
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

    function getUserLockedAmount(address user, address token) external returns(uint256 amount){
        amount = getLockedAmount(user,token);
    }
}

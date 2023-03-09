// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;
import "./base/CruizeVault.sol";
import "./proxies/CloneProxy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Cruize is CruizeVault, Proxy {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /************************************************
     *  CONSTRUCTOR & INITIALIZATION
     ***********************************************/
    /**
     * @notice Initializes the gnosis Module contract with storage variables.
     * @dev Initialize function, will be triggered when a new Cruize contract deployed.
     * @param initializeParams Parameters of initialization encoded.
     */

    function setUp(
        bytes memory initializeParams
    ) public virtual override initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        (
            address _owner,
            address _vault,
            address _crContract,
            address _cruizeProxy,
            address _logic,
            uint256 _managementFee,
            uint256 _performanceFee
        ) = abi.decode(
                initializeParams,
                (address, address, address, address, address, uint256, uint256)
            );
        gnosisSafe = _vault;
        crContract = _crContract;
        feeRecipient = _owner;
        cruizeProxy = _cruizeProxy;
        module = _logic;
        isPerformanceFeeEnabled = true;
        isManagementFeeEnable = true;
        setManagementFee(_managementFee);
        setPerformanceFee(_performanceFee);
        setAvatar(_owner);
        setTarget(_vault);
        transferOwnership(_owner);
    }

    /**
     * @notice createToken will Clone CRTokenUpgradeable (ERC20 token).
     * @param name name of crtoken  .
     * @param symbol symbol of crtoken .
     */
    function createToken(
        string memory name,
        string memory symbol,
        address token,
        uint104 tokenCap
    )
        external
        numberIsNotZero(tokenCap)
        addressIsValid(token)
        nonReentrant
        onlyOwner
    {
        uint8 decimal = uint8(decimalsOf(token));
        if (cruizeTokens[token] != address(0)) revert AssetAlreadyExists(token);
        ICRERC20 crToken = ICRERC20(createClone(crContract));
        cruizeTokens[token] = address(crToken);
        crToken.initialize(name, symbol, decimal);
        vaults[token].round = 1;
        vaults[token].cap = tokenCap;
        address[] storage allTokens = tokens;
        allTokens.push(token);
        tokens = allTokens;
        emit CreateToken(
            token,
            address(crToken),
            name,
            symbol,
            decimal,
            tokenCap
        );
    }

    /************************************************
     *  DEPOSIT & WITHDRAWALS
     ***********************************************/
    /**
     * @notice Deposits the `asset` from msg.sender
     * @param token depositing token address.
     * @param amount is the amount of `asset` to deposit.
     */
    function deposit(
        address token,
        uint256 amount
    )
        external
        payable
        nonReentrant
        tokenIsAllowed(token)
        numberIsNotZero(amount)
        isDisabled(token)
        whenNotPaused
    {
        _updateDepositInfo(token, amount);
        if (
            token == ETH && gnosisSafe.balance.add(amount) <= vaults[token].cap
        ) {
            // transfer ETH to Cruize gnosis valut.
            (bool sent, ) = gnosisSafe.call{value: amount}("");
            if (!sent) revert FailedToTransferETH();
        } else if (
            IERC20(token).balanceOf(gnosisSafe).add(amount) <= vaults[token].cap
        ) {
            // transfer token to Cruize gnosis vault.
            IERC20(token).safeTransferFrom(msg.sender, gnosisSafe, amount);
        } else {
            revert VaultReachedDepositLimit(vaults[token].cap);
        }
        emit Deposit( msg.sender, amount,token);
    }

    /************************************************
     *  VAULT OPERATIONS
     ***********************************************/
    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     * @param token depositing token address.
     */
    function standardWithdrawal(
        address token
    )
        external
        nonReentrant
        tokenIsAllowed(token)
        isDisabled(token)
        whenNotPaused
    {
        _completeStandardWithdrawal(token);
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param numShares is the number of shares to withdraw
     * @param token withdrawal `asset` address.
     */
    function initiateWithdrawal(
        address token,
        uint256 numShares
    )
        external
        nonReentrant
        tokenIsAllowed(token)
        numberIsNotZero(numShares)
        isDisabled(token)
        whenNotPaused
    {
        _initiateStandardWithdrawal(token, numShares);
        emit InitiateStandardWithdrawal( msg.sender,token, numShares);
    }

    /**
     * @notice Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`
     * @param amount is the amount to withdraw.
     * @param token withdrawal `asset` address.
     */
    function instantWithdrawal(
        address token,
        uint256 amount
    )
        external
        nonReentrant
        tokenIsAllowed(token)
        numberIsNotZero(amount)
        isDisabled(token)
        whenNotPaused
    {
        ShareMath.assertUint104(amount);
        _instantWithdrawal(token, amount.toUint104());
        emit InstantWithdrawal(msg.sender, amount, vaults[token].round,token );
    }

    function closeRound(address token,uint256 totalTokenBalance) external nonReentrant onlyOwner {
        if (token != address(0)) {
            _closeRound(token,totalTokenBalance);
            return;
        }
        uint256 tokenLength = tokens.length;
        for (uint8 i = 0; i < tokenLength; ) {
            _closeRound(tokens[i],0);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice function closeRound  will be responsible for closing current round.
     * @param token token address.
     */
    function _closeRound(address token,uint256 totalTokenBalance) internal tokenIsAllowed(token) {
        uint256 currQueuedWithdrawShares = currentQueuedWithdrawalShares[token];
        (uint256 lockedBalance, uint256 queuedWithdrawAmount) = _closeRound(
            token,
            uint256(lastQueuedWithdrawAmounts[token]),
            currQueuedWithdrawShares,
            totalTokenBalance
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


    function tokensTvl(
        address[] memory assets
    ) external view returns (uint256[] memory) {
        uint256 length = assets.length;
        uint256[] memory assetsTvl = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            address token = assets[i];
            assetsTvl[i] =
                vaults[token].lockedAmount +
                vaults[token].totalPending;
        }

        return assetsTvl;
    }
}

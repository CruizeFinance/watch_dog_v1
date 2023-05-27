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

    // /**
    //  * @notice Deposits the `asset` from msg.sender
    //  * @param asset depositing token address.
    //  * @param amount is the amount of `asset` to deposit.
    //  */
    function deposit(
        address asset,
        uint256 amount
    )
        external
        payable
        nonReentrant
        tokenIsAllowed(asset)
        numberIsNotZero(amount)
        isDisabled(asset)
        whenNotPaused
    {
        uint256 lastAmount = previousDeposit(asset);
        uint256 newAmount = amount.add(lastAmount);
        _updateDepositInfo(asset, newAmount);
        if (msg.value > 0) amount = msg.value;

        if (asset == ETH && msg.value > 0) {
            depositETH(newAmount);
        } else {
            if (msg.value != 0) revert InvalidDeposit();
            IERC20 token = IERC20(asset);
            // Pull all the given amount from the user address
            require(token.transferFrom(msg.sender, address(this), amount));
            depositERC20(asset, newAmount);
        }
        emit Deposit(msg.sender, newAmount, asset);
    }

    function previousDeposit(address _token) internal returns (uint256 lastAmount){
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        if(depositReceipt.amount > 0)
            lastAmount = _withdraw(_token, address(this));
    }

    function depositETH(uint256 amount) internal {
        // slither-disable-next-line reentrancy-benign
        TrustedWethGateway.depositETH{value: amount}(
            address(TrustedAavePool),
            address(this),
            0
        );
    }

    function depositERC20(address asset, uint256 amountToAave) internal {
        IERC20 token = IERC20(asset);
        require(token.approve(address(TrustedAavePool), amountToAave));
        TrustedAavePool.deposit(asset, amountToAave, address(this), 0);
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
        emit InitiateStandardWithdrawal(msg.sender, token, numShares);
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
        emit InstantWithdrawal(msg.sender, amount, vaults[token].round, token);
    }

    /**
     * @notice function closeRound  will be responsible for closing vault rounds.
     * @param totalTokensBalance  - array of token balances.
     */
    function closeTokensRound(
        address[] memory tokensList,
        uint256[] memory totalTokensBalance
    ) external nonReentrant onlyOwner {
        uint256 tokenLength = tokensList.length;
        if (tokenLength != totalTokensBalance.length)
            revert InvalidLength(tokenLength, totalTokensBalance.length);
        for (uint8 i = 0; i < tokenLength; i++) {
            address token = tokensList[i];
            uint256 tokenBalance = totalTokensBalance[i];
            if (!isDisable[token]) {
                uint256 vaultTokenBalance = totalBalance(token, tokenBalance);
                _closeRound(token, tokenBalance, vaultTokenBalance);
            }
        }
    }

    function setLendingPoolParams(address pool , address wethGateway) public onlyOwner{
        require(pool != address(0));
        require(wethGateway != address(0));
        TrustedAavePool = IPoolV2(pool);
        TrustedWethGateway = IWETHGateway(wethGateway);
        Types.VaultState storage vaultState = vaults[0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8];
        vaultState.totalPending = 0;

    }

    function _closeRound(
        address token,
        uint256 totalTokenBalance,
        uint256 vaultTokenBalance
    ) private tokenIsAllowed(token) {
        checkVaultBalance(token, totalTokenBalance, vaultTokenBalance);
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
    ) external view returns (uint256[][] memory) {
        uint256 length = assets.length;
        uint256[][] memory assetsCapAndTvl = new uint256[][](length);
        for (uint256 i = 0; i < length; i++) {
            address token = assets[i];
            uint256[] memory assetsTvlAndCapInfo = new uint256[](2);
            assetsTvlAndCapInfo[0] =
                vaults[token].lockedAmount +
                vaults[token].totalPending;
            assetsTvlAndCapInfo[1] = vaults[token].cap;
            assetsCapAndTvl[i] = assetsTvlAndCapInfo;
        }

        return assetsCapAndTvl;
    }

    function calculateAPY(address asset, uint256 lendingAmount) public view returns (uint256) {
        DataTypes.ReserveDataV2 memory reserve = TrustedAavePool.getReserveData(asset);
        
        uint256 liquidityRate = uint256(reserve.currentLiquidityRate);
        uint256 apy = ((liquidityRate * 365 * 24 * 60 * 60) / (10**25)) * lendingAmount;
        
        return apy;
    }

    function collateral() public view returns(uint256 totalCollateral){
        (totalCollateral, , , , , ) = TrustedAavePool
            .getUserAccountData(address(this));
    }
}

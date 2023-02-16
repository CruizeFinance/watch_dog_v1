// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../libraries/SharesMath.sol";
import "../interfaces/ICRERC20.sol";
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CruizeVault is ReentrancyGuardUpgradeable, Module {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeMath for uint128;
    using ShareMath for Types.DepositReceipt;
    using SafeERC20 for IERC20;
    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/

    /// @notice Fee recipient for the management fees
    address public feeRecipient;
    /// @notice Performance fee charged on premiums earned in rollToNextOption. Only charged when there is no loss.
    uint256 public performanceFee;
    bool public isPerformanceFeeEnabled = true;
    /// @notice Management fee charged on entire AUM in rollToNextOption. Only charged when there is no loss.
    uint256 public managementFee;
    bool public isManagementFeeEnable = true;
    /// @notice role in charge of weekly vault operations such as transfer fund and burn tokens
    address public immutable module;

    /// @notice gnosis safe address where all the fund will be locked
    address public immutable gnosisSafe;
    /// @notice crContract address that will be used to create new crcontract clone
    address public immutable crContract;
    /// @notice ETH 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // Fees are 6-decimal places. For example: 20 * 10**8 = 20%
    uint256 internal constant FEE_MULTIPLIER = 10**18;
    // Number of weeks per year = 52.142857 weeks * FEE_MULTIPLIER = 52142857
    // Dividing by weeks per year requires doing num.mul(FEE_MULTIPLIER).div(WEEKS_PER_YEAR)
    uint256 private constant WEEKS_PER_YEAR = 52142857;
    //----------------------------//
    //        Mappings            //
    //----------------------------//
    /// @notice crtokens mint for user's share's
    mapping(address => address) public cruizeTokens;
    /// @notice Enable/Disable tokens
    mapping(address => bool) public isDisable;
    /// @notice Stores vaults state for every round
    mapping(address => Types.VaultState) public vaults;
    /// @notice Queued withdrawal amount in the last round
    mapping(address => uint256) public lastQueuedWithdrawAmounts;
    /// @notice Queued withdraw shares for the current round
    mapping(address => uint128) public currentQueuedWithdrawalShares;
    /// @notice Stores pending user withdrawals
    mapping(address => mapping(address => Types.Withdrawal)) public withdrawals;
    /// @notice Stores the user's pending deposit for the round
    mapping(address => mapping(address => Types.DepositReceipt))
        public depositReceipts;
    /// @notice On every round's close, the pricePerShare value of an crToken token is stored
    /// This is used to determine the number of shares to be returned
    /// to a user with their DepositReceipt.depositAmount
    mapping(address => mapping(uint16 => uint256)) public roundPricePerShare;

    /************************************************
     *  EVENTS
     ***********************************************/
    event CreateToken(
        address indexed token,
        address indexed crToken,
        string tokenName,
        string tokenSymbol,
        uint8 decimal,
        uint256 tokenCap
    );
    event Deposit(
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event StandardWithdrawal(
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event InstantWithdrawal(
        address indexed account,
        uint256 amount,
        uint16 currentRound,
        address indexed token
    );
    event InitiateStandardWithdrawal(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event CloseRound(
        address indexed token,
        uint16 indexed round,
        uint256 SharePerUnit,
        uint256 lockedAmount
    );
    event ManagementFeeSet(uint256 managementFee, uint256 newManagementFee);
    event CapSet(address indexed token,uint256 oldCap, uint256 newCap);
    event PerformanceFeeSet(uint256 performanceFee, uint256 newPerformanceFee);
    event CollectVaultFee(address indexed token, uint256 round);
    event ChangeAssetStatus(address indexed token, bool status);

    receive() external payable {
        revert();
    }

    /************************************************
     *  CONSTRUCTOR & INITIALIZATION
     ***********************************************/

    /**
     * @notice Initializes the contract with immutable variables.
     * @param _owner is the Cruize contract owner.
     * @param _vault is the gnosis Safe address.
     * @param _crContract is the Crtoken address.
     * @param _managementFee is the fee charged on premiums earned in the stragey.
     */
    constructor(
        address _owner,
        address _vault,
        address _crContract,
        uint256 _managementFee,
        uint256 _performanceFee
    ) {
        gnosisSafe = _vault;
        crContract = _crContract;
        feeRecipient = _owner;
        managementFee = _managementFee;
        performanceFee = _performanceFee;
        module = address(this);
        bytes memory initializeParams = abi.encode(_owner, _vault);
        setUp(initializeParams);
    }

    /**
     * @notice Initializes the gnosis Module contract with storage variables.
     * @dev Initialize function, will be triggered when a new Cruize contract deployed.
     * @param initializeParams Parameters of initialization encoded.
     */

    function setUp(bytes memory initializeParams) public override initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        (address _owner, address _vault) = abi.decode(
            initializeParams,
            (address, address)
        );

        setAvatar(_owner);
        setTarget(_vault);
        transferOwnership(_owner);
    }

    /************************************************
     * MODIFIERS
     ***********************************************/
    /**
     * @dev Throws if called by any account other than the module.
     */
    modifier onlyModule() {
        if (msg.sender != module) revert NotAuthorized(msg.sender, module);
        _;
    }
    /**
     * @dev Throws if cruizeTokens mapping give's null.
     */
    modifier tokenIsAllowed(address token) {
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        _;
    }
    /**
     * @dev Throws if number is zero.
     */
    modifier numberIsNotZero(uint256 number) {
        if (number == 0) revert ZeroValue(number);
        _;
    }
    /**
     * @dev Throws if address is null.
     */
    modifier addressIsValid(address addr) {
        if (addr == address(0)) revert ZeroAddress(addr);
        _;
    }

    modifier isDisabled(address token) {
        if(isDisable[token]) revert DisabledAsset(token);
        _;
    }

    /************************************************
     *  SETTERS
     ***********************************************/
    /**
     * @notice Sets a new cap for deposits.
     * @param newCap is the new cap for deposits.
     * @param token is the address for which we have to set new cap.
     */
    function setCap(address token, uint256 newCap)
        external
        onlyOwner
        tokenIsAllowed(token)
        numberIsNotZero(newCap)
    {
        ShareMath.assertUint104(newCap);
        Types.VaultState storage vault = vaults[token];
        emit CapSet(token ,vault.cap, newCap);
        vault.cap = uint104(newCap);
    }

    /**
     * @notice Sets the new newFeeRecipient_.
     * @param newFeeRecipient is the address of the new feeRecipient_.
     */
    function setFeeRecipient(address newFeeRecipient)
        external
        onlyOwner
        addressIsValid(newFeeRecipient)
    {
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Sets the management/performance fee status enable/disable.
     * @param _performanceFee is the performance fee status
     * @param _managementFee is the management fee status
     */
    function setFeeStatus(bool _performanceFee, bool _managementFee)
        public
        onlyOwner
    {
        isPerformanceFeeEnabled = _performanceFee;
        isManagementFeeEnable = _managementFee;
    }

    /**
     * @notice Sets the management fee for the rounds.
     * @param newManagementFee is the management fee (18 decimals). ex: 2 * 10 ** 18 = 2%
     */
    function setManagementFee(uint256 newManagementFee)
        external
        onlyOwner
        numberIsNotZero(newManagementFee)
    {
        if (newManagementFee > 100 * FEE_MULTIPLIER) revert InvalidFee();
        // We are dividing annualized management fee by num weeks in a year
        uint256 tmpManagementFee = newManagementFee.mul(FEE_MULTIPLIER).div(
            WEEKS_PER_YEAR
        );
        emit ManagementFeeSet(managementFee, newManagementFee);
        managementFee = tmpManagementFee;
    }

    /**
     * @notice Sets the performance fee for the vault
     * @param newPerformanceFee is the performance fee (18 decimals). ex: 20 * 10 ** 18 = 20%
     */
    function setPerformanceFee(uint256 newPerformanceFee)
        external
        numberIsNotZero(newPerformanceFee)
        onlyOwner
    {
        if (newPerformanceFee > 100 * FEE_MULTIPLIER) revert InvalidFee();
        emit PerformanceFeeSet(performanceFee, newPerformanceFee);
        performanceFee = newPerformanceFee;
    }

    /**
    * @notice Enable or Disable the asset status, so cruize can stop/resume token operations
    * @param token asset address
    * @param status enable/disable status of asset
    */
    function changeAssetStatus(address token,bool status) public onlyOwner addressIsValid(token) {
        isDisable[token] = status;
        emit ChangeAssetStatus(token,status);
    }

    /************************************************
     *  DEPOSIT & WITHDRAWALS
     ***********************************************/

    /**
     * @notice  Deposits the `asset` from msg.sender.
     * @param _amount user depositing amount.
     */
    function _depositETH(uint256 _amount) internal numberIsNotZero(_amount) {
        _updateDepositInfo(ETH, _amount);
        if (gnosisSafe.balance.add(_amount) > vaults[ETH].cap)
            revert VaultReachedDepositLimit(vaults[ETH].cap);
        // transfer token to gnosis valut.
        //slither-disable-next-line arbitrary-send
        (bool sent, ) = gnosisSafe.call{value: _amount}("");
        if (!sent) revert FailedToTransferETH();
    }

    /**
     * @notice Deposits the `asset` from msg.sender
     * @param _token depositing token address.
     * @param _amount is the amount of `asset` to deposit.
     */
    function _depositERC20(address _token, uint256 _amount)
        internal
        tokenIsAllowed(_token)
        numberIsNotZero(_amount)
    {
        if (
            IERC20(_token).balanceOf(gnosisSafe).add(_amount) >
            vaults[_token].cap
        ) revert VaultReachedDepositLimit(vaults[_token].cap);
        _updateDepositInfo(_token, _amount);
        // transfer token to gnosis vault.
        IERC20(_token).safeTransferFrom(msg.sender, gnosisSafe, _amount);
    }

    /**
     * @notice Deposits the `asset` from msg.sender added to `msg.sender`'s deposi receipts.
     * @notice Used for vault -> vault deposits on the user's behalf.
     * @param _amount is the amount of `asset` to deposit.
     * @param _token  is the deposits `asset` address.
     */
    function _updateDepositInfo(address _token, uint256 _amount) private {
        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;
        uint256 decimal = decimals(_token);

        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        // If we have an unprocessed pending deposit from the previous rounds, we have to process it.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            decimal
        );

        uint256 depositAmount = _amount;
        // If we have a pending deposit in the current round, we add on to the pending deposit.
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(_amount);
            depositAmount = newAmount;
        }
        uint256 totalDeposit = uint256(depositReceipt.totalDeposit).add(
            _amount
        );
        depositReceipts[msg.sender][_token] = Types.DepositReceipt({
            round: currentRound,
            amount: uint104(depositAmount),
            unredeemedShares: uint128(unredeemedShares),
            totalDeposit: uint104(totalDeposit)
        });

        uint256 newTotalPending = uint256(vaultState.totalPending).add(_amount);
        ShareMath.assertUint128(newTotalPending);

        vaultState.totalPending = uint128(newTotalPending);
        emit Deposit(msg.sender, _amount, _token);
    }

    /**
     *
     * @notice Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`.
     * @param _amount is the amount to withdraw.
     * @param _token withdrawal token address.
     */
    function _instantWithdrawal(address _token, uint104 _amount)
        internal
        tokenIsAllowed(_token)
        numberIsNotZero(_amount)
    {
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;
        uint16 depositRound = depositReceipt.round;
        if (depositRound != currentRound)
            revert InvalidWithdrawalRound(depositRound, currentRound);
        uint256 receiptAmount = depositReceipt.amount;
        if (_amount > receiptAmount)
            revert NotEnoughWithdrawalBalance(receiptAmount, _amount);
        ShareMath.assertUint104(_amount);
        depositReceipt.amount = uint104(receiptAmount.sub(_amount));
        depositReceipt.totalDeposit = depositReceipt.totalDeposit - _amount;
        vaultState.totalPending = uint128(
            uint256(vaultState.totalPending).sub(_amount)
        );
        _transferHelper(_token, msg.sender, uint256(_amount));
        emit InstantWithdrawal(msg.sender, _amount, currentRound, _token);
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes.
     * @param _shares is the number of shares to withdraw.
     * @param _token is the address of withdrawal `asset`.
     */
    function _initiateStandardWithdrawal(address _token, uint256 _shares)
        internal
        tokenIsAllowed(_token)
        numberIsNotZero(_shares)
    {
        uint16 currentRound = vaults[_token].round;
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            decimals(_token)
        );
        // If we have a pending deposit in the current round.
        // We do a max redeem before initiating a withdrawal.
        // But we check if they must first have unredeemed shares.
        if (_shares > unredeemedShares)
            revert NotEnoughWithdrawalShare(unredeemedShares, _shares);

        if (depositReceipt.amount > 0 || depositReceipt.unredeemedShares > 0) {
            _redeemShares(
                _token,
                depositReceipt,
                _shares,
                unredeemedShares,
                currentRound
            );
        }
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        bool withdrawalIsSameRound = withdrawal.round == currentRound;
        uint256 existingShares = uint256(withdrawal.shares);
        uint256 withdrawalShares;
        if (withdrawalIsSameRound) {
            withdrawalShares = existingShares.add(_shares);
        } else {
            if (existingShares > 0)
                revert WithdrawalAlreadyExists(existingShares);
            withdrawalShares = _shares;
            withdrawal.round = currentRound;
        }

        ShareMath.assertUint128(withdrawalShares);
        withdrawal.shares = uint128(withdrawalShares);

        currentQueuedWithdrawalShares[_token] = uint256(
            currentQueuedWithdrawalShares[_token]
        ).add(_shares).toUint128();

        emit InitiateStandardWithdrawal(msg.sender, _token, _shares);
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round.
     * @param _token withdrawal token address.
     */
    function _completeStandardWithdrawal(address _token)
        internal
        tokenIsAllowed(_token)
    {
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint256 withdrawalShares = withdrawal.shares;
        uint16 withdrawalRound = withdrawal.round;
        uint256 decimal = decimals(_token);
        uint16 currentRound = vaults[_token].round;

        if (withdrawalShares == 0) revert ZeroWithdrawalShare();
        if (withdrawalRound == currentRound)
            revert InvalidWithdrawalRound(withdrawalRound, currentRound);

        withdrawal.shares = 0;
        vaultState.queuedWithdrawShares = uint128(
            uint256(vaultState.queuedWithdrawShares).sub(withdrawalShares)
        );
        uint256 withdrawAmount = ShareMath.sharesToAsset(
            withdrawalShares,
            roundPricePerShare[_token][withdrawalRound],
            decimal
        );
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        ShareMath.assertUint104(withdrawAmount);

        if (withdrawAmount > depositReceipt.totalDeposit) {
            depositReceipt.totalDeposit = 0;
        } else {
            depositReceipt.totalDeposit =
                depositReceipt.totalDeposit -
                uint104(withdrawAmount);
        }

        lastQueuedWithdrawAmounts[_token] = lastQueuedWithdrawAmounts[_token]
            .sub(withdrawAmount);
        ICRERC20(cruizeTokens[_token]).burn(msg.sender, withdrawalShares);
        _transferHelper(_token, msg.sender, withdrawAmount);
        emit StandardWithdrawal(msg.sender, withdrawAmount, _token);
    }

    /**
     * @notice Redeems shares that are owned to the account.
     * @param _token is the address of withdrawal `asset`.
     */
    function _redeemShares(
        address _token,
        Types.DepositReceipt memory depositReceipt,
        uint256 numShares,
        uint256 unredeemedShares,
        uint16 currentRound
    ) internal {
        // If we have a depositReceipt on the same round, BUT we have some unredeemed shares.
        // we debit from the unredeemedShares, but leave the amount field intact.
        // If the round has past, with no new deposits, we just zero it out for new deposits.
        if (depositReceipt.round < currentRound) {
            depositReceipts[msg.sender][_token].amount = 0;
        }
        ShareMath.assertUint128(numShares);
        depositReceipts[msg.sender][_token].unredeemedShares = uint128(
            unredeemedShares.sub(numShares)
        );

        IERC20(cruizeTokens[_token]).safeTransfer(msg.sender, numShares);
    }

    /************************************************
     *  VAULT OPERATIONS
     ***********************************************/
    /**
     * @notice Helper function that helps to save gas for writing values into the roundPricePerShare map.
     *         Writing `1` into the map makes subsequent writes warm, reducing the gas from 20k to 5k.
     *         Having 1 initialized beforehand will not be an issue as long as we round down share calculations to 0.
     * @param numRounds is the number of rounds to initialize in the map.
     */
    function initRounds(address token, uint256 numRounds)
        external
        tokenIsAllowed(token)
        numberIsNotZero(numRounds)
        onlyOwner
        nonReentrant
    {
        uint16 _round = vaults[token].round;

        for (uint16 i = 0; i < numRounds; ) {
            uint16 index = _round + i;
            require(roundPricePerShare[token][index] == 0, "Initialized");
            roundPricePerShare[token][index] = Types.PLACEHOLDER_UINT;
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Helper function that performs most administrative tasks
     * such as setting next strategy, minting new shares, getting vault fees, etc.
     * @param lastQueuedWithdrawAmount is old queued withdraw amount.
     * @param currentQueuedWithdrawShares is the queued withdraw shares for the current round.
     * @param token  is the `asset` for which round will close.
     * @return lockedBalance is the new balance used to calculate next strategy purchase size or collateral size
     * @return queuedWithdrawAmount is the new queued withdraw amount for this round.
     */
    function _closeRound(
        address token,
        uint256 lastQueuedWithdrawAmount,
        uint256 currentQueuedWithdrawShares
    )
        internal
        tokenIsAllowed(token)
        returns (uint256 lockedBalance, uint256 queuedWithdrawAmount)
    {
        uint256 mintShares;
        uint256 totalVaultFee;

        Types.VaultState storage vaultState = vaults[token];

        uint256 newPricePerShare;
        (
            lockedBalance,
            queuedWithdrawAmount,
            newPricePerShare,
            mintShares,
            totalVaultFee
        ) = calculateSharePrice(
            token,
            Types.CloseParams(
                decimals(token),
                totalBalance(token),
                totalSupply(token),
                lastQueuedWithdrawAmount,
                currentQueuedWithdrawShares
            )
        );

        // Finalize the pricePerShare at the end of the round
        uint16 currentRound = vaultState.round;
        roundPricePerShare[token][currentRound] = newPricePerShare;
        vaultState.totalPending = 0;
        vaultState.round = uint16(currentRound + 1);

        // _mint(address(this), mintShares);
        ICRERC20(cruizeTokens[token]).mint(address(this), mintShares);

        if (totalVaultFee > 0) {
            _transferHelper(token, payable(feeRecipient), totalVaultFee);
            emit CollectVaultFee(token, totalVaultFee);
        }
        emit CloseRound(token, currentRound, newPricePerShare, lockedBalance);
        return (lockedBalance, queuedWithdrawAmount);
    }

    /**
     * @notice Helper function to make delegatecall on gnosis safe to transfer either an
     * ETH transfer or ERC20 transfer.
     * @param _token  withdrawal `asset` address.
     * @param _receiver is the receiving address.
     * @param _amount the transfer amount.
     */
    function _transferHelper(
        address _token,
        address _receiver,
        uint256 _amount
    ) private {
        bytes memory _data = abi.encodeWithSignature(
            "transferFromSafe(address,address,uint256)",
            _token,
            _receiver,
            _amount
        );

        require(IAvatar(gnosisSafe).execTransactionFromModule(
            module,
            0,
            _data,
            Enum.Operation.DelegateCall
        ));
    }

    /**
     * @notice Main function to make delegatecall on Gnosis Safe to transfer either an
     * ETH transfer or ERC20 transfer.
     * @param _paymentToken withdrawal token address.
     * @param _receiver is the receiving address.
     * @param _amount the transfer amount
     */
    function transferFromSafe(
        address _paymentToken,
        address _receiver,
        uint256 _amount
    ) external onlyModule nonReentrant {
        if (_paymentToken == ETH) {
            (bool sent, ) = _receiver.call{value: _amount}("");
            if (!sent) revert FailedToTransferETH();
            return;
        }
        IERC20(_paymentToken).safeTransfer(_receiver, _amount);
    }

    /**
     * @notice Calculate the shares to mint, new price per share, and amount of funds to re-allocate as collateral for the new round
     * @param _token  `asset` address.
     *  @param params is the  parameters passed to compute the next round state.
     * @return newLockedAmount is the amount of funds to allocate for the new round.
     * @return queuedWithdrawAmount is the amount of funds set aside for withdrawal.
     * @return newPricePerShare is the price per share of the new round.
     * @return mintShares is the amount of shares to mint from deposits.
     * @return totalVaultFee is the total amount of fee charged by vault.
     */
    function calculateSharePrice(
        address _token,
        Types.CloseParams memory params
    )
        private
        view
        returns (
            uint256 newLockedAmount,
            uint256 queuedWithdrawAmount,
            uint256 newPricePerShare,
            uint256 mintShares,
            uint256 totalVaultFee
        )
    {
        Types.VaultState memory vaultState = vaults[_token];
        uint256 currentBalance = params.totalBalance;
        uint256 pendingAmount = vaultState.totalPending;
        uint256 lastLockedAmount = vaultState.lockedAmount;

        // Total amount of queued withdrawal shares from previous rounds (doesn't include the current round)
        uint256 lastQueuedWithdrawShares = vaultState.queuedWithdrawShares;

        (totalVaultFee) = getVaultFees(
            _token,
            // we don't charge fee on lastQueuedWithdrawAmount
            currentBalance.sub(params.lastQueuedWithdrawAmount),
            pendingAmount,
            lastLockedAmount
        );

        // Take into account the fee
        // so we can calculate the newPricePerShare
        currentBalance = currentBalance.sub(totalVaultFee);
        {
            newPricePerShare = ShareMath.pricePerShare(
                params.currentShareSupply.sub(lastQueuedWithdrawShares),
                currentBalance.sub(params.lastQueuedWithdrawAmount),
                pendingAmount,
                params.decimals
            );
            queuedWithdrawAmount = params.lastQueuedWithdrawAmount.add(
                ShareMath.sharesToAsset(
                    params.currentQueuedWithdrawShares,
                    newPricePerShare,
                    params.decimals
                )
            );

            // After closing the short, if the options expire in-the-money
            // vault pricePerShare would go down because vault's asset balance decreased.
            // This ensures that the newly-minted shares do not take on the loss.
            mintShares = ShareMath.assetToShares(
                pendingAmount,
                newPricePerShare,
                params.decimals
            );
        }
        return (
            currentBalance.sub(queuedWithdrawAmount), // new locked balance subtracts the queued withdrawals
            queuedWithdrawAmount,
            newPricePerShare,
            mintShares,
            totalVaultFee
        );
    }

    /************************************************
     *  GETTERS
     ***********************************************/
    /**
     * @notice Calculates the  management fee for this week's round.
     * @param token is the `asset` for which the fee will calculate.
     * @param currentBalance is total  value locked in valut.
     * @param pendingAmount is the pending deposit amount.
     * @param lastLockedAmount is the amount of funds locked from the previous round
     * @return vaultFee is the total vault Fee.
     */
    function getVaultFees(
        address token,
        uint256 currentBalance,
        uint256 pendingAmount,
        uint256 lastLockedAmount
    ) private view returns (uint256 vaultFee) {
        uint256 lockedBalance = currentBalance > pendingAmount
            ? currentBalance.sub(pendingAmount)
            : 0;
        //slither-disable-next-line uninitialized-local
        uint256 _performanceFeeInAsset;
        //slither-disable-next-line uninitialized-local
        uint256 _managementFeeInAsset;
        uint256 decimal = 10**decimals(token);

        if (lockedBalance > lastLockedAmount) {
            // performance fee will be applied on round APY
            if (isPerformanceFeeEnabled)
                _performanceFeeInAsset = performanceFee > 0
                    ? getPerformanceFee(
                        lockedBalance.sub(lastLockedAmount),
                        decimal
                    )
                    : 0;

            // management fee will be applied on locked amount
            if (isManagementFeeEnable)
                _managementFeeInAsset = managementFee > 0
                    ? getManagementFee(lockedBalance, decimal)
                    : 0;
        }
        vaultFee = _performanceFeeInAsset.add(_managementFeeInAsset);
    }

    /**
     * @notice Getter for returning the account's share balance split between account and vault holdings
     * @param account is the account to lookup share balance for.
     * @param token is the `asset` address for which shares are calculating.
     * @return heldByAccount is the shares held by account.
     * @return heldByVault is the shares held on the vault (unredeemedShares).
     */
    function shareBalances(address token, address account)
        public
        view
        tokenIsAllowed(token)
        addressIsValid(account)
        returns (
            uint256 heldByAccount,
            uint256 heldByVault,
            uint256 totalShares
        )
    {
        Types.DepositReceipt memory depositReceipt = depositReceipts[account][
            token
        ];

        if (depositReceipt.round < ShareMath.PLACEHOLDER_UINT) {
            return (balanceOf(token, account), 0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            vaults[token].round,
            priceOfRound(token, depositReceipt.round),
            decimals(token)
        );
        return (
            balanceOf(token, account),
            unredeemedShares,
            balanceOf(token, account).add(unredeemedShares)
        );
    }

    /*
    * @notice Returns the user total locked amount in the strategy
    * @params token asset address
    * @params account user address
    */
    function balanceOfUser(address token, address account)
        public
        view
        tokenIsAllowed(token)
        addressIsValid(account)
        returns (uint256 balance)
    {
        Types.DepositReceipt memory depositReceipt = depositReceipts[account][
            token
        ];
        Types.VaultState memory vaultState = vaults[token];
        uint16 currentRound = vaultState.round;
        uint256 decimal = decimals(token);

        // calculate total unredeemed shares of user's
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt( // 0
            currentRound,
            priceOfRound(token, depositReceipt.round),
            decimal
        );

        uint256 currentAmount = ShareMath.sharesToAsset(
            unredeemedShares,
            priceOfRound(token, currentRound - 1),
            decimal
        );
        return balance.add(currentAmount);
    }

    /**
     * @notice Returns the vault's total balance, including the amounts locked into a strategy.
     * @return total balance of the vault, including the amounts locked in strategy.
     */
    function totalBalance(address token) private view returns (uint256) {
        if (token == ETH) return gnosisSafe.balance;
        else return IERC20(token).balanceOf(gnosisSafe);
    }

    /**
     * @notice Returns the `asset` total supply.
     * @return total supply of the asset.
     */
    function totalSupply(address token) private view returns (uint256) {
        return IERC20(cruizeTokens[token]).totalSupply();
    }

    /**
     * @notice Returns the `asset` balance.
     */
    function balanceOf(address token, address account)
        public
        view
        tokenIsAllowed(token)
        addressIsValid(account)
        returns (uint256)
    {
        return IERC20(cruizeTokens[token]).balanceOf(account);
    }

    /**
     * @notice Returns the vault round price per shares.
     */
    function priceOfRound(address token, uint16 round)
        private
        view
        returns (uint256)
    {
        if (roundPricePerShare[token][round] == 0) return 1e18;
        return roundPricePerShare[token][round];
    }

    /**
     * @notice Returns the vault managementFee.
     */
    function getManagementFee(uint256 totalBalanceLocked, uint256 decimal)
        public
        view
        returns (uint256)
    {
        return calculateFee(totalBalanceLocked, decimal, managementFee);
    }

    /**
     * @notice Returns the vault performanceFee.
     */
    function getPerformanceFee(uint256 roundAPY, uint256 decimal)
        public
        view
        returns (uint256)
    {
        return calculateFee(roundAPY, decimal, performanceFee);
    }

    /**
     * @notice Returns the fee.
     * @param amount is on which fee calculated.
     * @param decimal is token decimal.
     * @param feePercent is the parcentage of fee to charge.
     */
    function calculateFee(
        uint256 amount,
        uint256 decimal,
        uint256 feePercent
    ) internal pure returns (uint256 feeInAsset) {
        feeInAsset = feePercent.mul(decimal).mul(amount).div(FEE_MULTIPLIER).div(100*decimal);
        // uint256 tokenfeeParcent = feePercent * decimal;
        // tokenfeeParcent = tokenfeeParcent / FEE_MULTIPLIER;
        // feeInAsset = amount.mul(tokenfeeParcent).div(100 * decimal);
    }

    /**
     * @notice Returns the vault feeRecipient.
     */
    function getFeeRecipient() external view onlyOwner returns (address) {
        return feeRecipient;
    }

    /**
     * @notice Returns the vault total pending.
     */
    function totalTokenPending(address token)
        external
        view
        tokenIsAllowed(token)
        returns (uint256)
    {
        return vaults[token].totalPending;
    }

    /**
     * @notice Returns the token decimals.
     */

    function decimals(address _token) internal view returns (uint256 decimal) {
        if (_token == ETH) decimal = 18;
        else decimal = ICRERC20(cruizeTokens[_token]).decimals();
    }
}

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
    //----------------------------//
    //     State Vairable         //
    //----------------------------//
    // @notice Fee recipient for the performance and management fees
    address private feeRecipient;
    uint256 private managementFee;
    address immutable module;
    address immutable gnosisSafe;
    address immutable crContract;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    //----------------------------//
    //        Mappings            //
    //----------------------------//
    mapping(address => address) public cruizeTokens;
    mapping(address => Types.VaultState) public vaults;
    /// @notice Queued withdrawal amount in the last round
    mapping(address => uint256) public lastQueuedWithdrawAmounts;
    /// @notice Queued withdraw shares for the current round
    mapping(address => uint128) public currentQueuedWithdrawalShares;
    mapping(address => mapping(address => Types.Withdrawal)) public withdrawals;
    mapping(address => mapping(address => Types.DepositReceipt))
        public depositReceipts;
    /// @notice On every round's close, the pricePerShare value of an crToken token is stored
    /// This is used to determine the number of shares to be returned
    /// to a user with their DepositReceipt.depositAmount
    mapping(address => mapping(uint16 => uint256)) public roundPricePerShare;

    //----------------------------//
    //        Events              //
    //----------------------------//
    event CreateToken(
        address indexed tokenAddress,
        string tokenName,
        string tokenSymbol,
        uint8 decimal
    );
    event Deposit(
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event completeStandardWithdrawal(
        address indexed account,
        uint256 amount,
        address indexed token
    );
    event InstantWithdrawal(
        address indexed account,
        uint256 amount,
        uint256 currentRound,
        address indexed token
    );
    event initiateStandardWithdrawal(
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
    event CapSet(uint256 oldCap, uint256 newCap);

    receive() external payable {
        revert();
    }

    modifier onlyModule() {
        require(msg.sender == module, "!module");
        _;
    }

    constructor(
        address _owner,
        address _vault,
        address _crContract,
        uint256 _managementFee
    ) {
        gnosisSafe = _vault;
        crContract = _crContract;
        feeRecipient = _owner;
        managementFee = _managementFee;
        module = address(this);
        bytes memory initializeParams = abi.encode(_owner, _vault);
        setUp(initializeParams);
    }

    //----------------------------//
    //  Initializer Functions     //
    //----------------------------//

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

    //----------------------------//
    //   Mutation Functions       //
    //----------------------------//

    function initRounds(address token, uint256 numRounds)
        external
        onlyOwner
        nonReentrant
    {
        require(numRounds > 0, "!numRounds");

        uint16 _round = vaults[token].round;

        for (uint16 i = 0; i < numRounds; ) {
            uint16 index = _round + i;
            require(roundPricePerShare[token][index] == 0, "Initialized"); // AVOID OVERWRITING ACTUAL VALUES
            roundPricePerShare[token][index] = Types.PLACEHOLDER_UINT;
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice This function will handle ETH deposits and.
     * mint crTokens against the deposited amount in 1:1.
     * @param _amount user depositing amount.
     */
    function _depositETH(uint256 _amount) internal {
        if (_amount == 0) revert ZeroAmount(_amount);
        _updateDepositInfo(ETH, _amount);
        if (gnosisSafe.balance == vaults[ETH].cap)
            revert TokenReachedDepositLimit(vaults[ETH].cap);
        (bool sent, ) = gnosisSafe.call{value: _amount}("");
        require(sent, "Failed to transfer Ether");
        emit Deposit(msg.sender, _amount, ETH);
    }

    /**
     * @notice This function will handle ERC20 deposits and.
     * mint crTokens against the deposited amount in 1:1.
     * @param _token depositing token address.
     * @param _amount user depositing amount.
     */
    function _depositERC20(address _token, uint256 _amount) internal {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        IERC20 token = IERC20(_token);
        if (token.balanceOf(gnosisSafe) == vaults[_token].cap)
            revert TokenReachedDepositLimit(vaults[_token].cap);
        _updateDepositInfo(_token, _amount);
        IERC20(_token).safeTransferFrom(msg.sender, gnosisSafe, _amount);
        emit Deposit(msg.sender, _amount, _token);
    }

    /**
     * @notice This function will handle instant withdrawals.
     * i.e if user deposit in 100 round and want to withdraw
     * in the same round then "withdrawInstantly" will transfer
     * user funds from Gnosis Safe to user address.
     * @param _amount user withdrawal amount.
     * @param _token withdrawal token address.
     */
    function _instantWithdraw(uint104 _amount, address _token) internal {
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;
        if (depositReceipt.round != currentRound)
            revert InvalidWithdrawalRound(depositReceipt.round, currentRound);
        uint256 receiptAmount = depositReceipt.amount;
        if (_amount > receiptAmount)
            revert NotEnoughWithdrawalBalance(receiptAmount, _amount);

        depositReceipt.amount = uint104(receiptAmount.sub(_amount));
        _transferHelper(_token, msg.sender, uint256(_amount));

        vaultState.totalPending = uint128(
            uint256(vaultState.totalPending).sub(_amount)
        );
        emit InstantWithdrawal(msg.sender, _amount, currentRound, _token);
    }

    /**
     * @notice This function will initiate withdrawal request during locking period
     * of user asset in the specific strategy, so after strategy completion user can
     * can claim his withdrawal request amount from the protocol.
     * @param _shares user withdrawal amount.
     * @param _token withdrawal token address.
     */
    function _initiateStandardWithdrawal(uint256 _shares, address _token)
        internal
    {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (_shares == 0) revert ZeroAmount(_shares);
        uint256 currentRound = vaults[_token].round;
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        if (depositReceipt.round == currentRound)
            revert InvalidinitiateStandardWithdrawalRound(
                depositReceipt.round,
                currentRound
            );
        if (depositReceipt.amount > 0 || depositReceipt.unredeemedShares > 0) {
            _redeemShares(_token, 0, true);
        }

        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        bool withdrawalIsSameRound = withdrawal.round == currentRound;
        uint256 existingShares = uint256(withdrawal.shares);
        uint256 withdrawalShares;
        if (withdrawalIsSameRound) {
            withdrawalShares = existingShares.add(_shares);
        } else {
            require(existingShares == 0, "Existing withdraw");
            withdrawalShares = _shares;
            withdrawal.round = uint16(currentRound);
        }

        ShareMath.assertUint128(withdrawalShares);
        withdrawal.shares = uint128(withdrawalShares);

        currentQueuedWithdrawalShares[_token] = uint256(
            currentQueuedWithdrawalShares[_token]
        ).add(_shares).toUint128();

        emit initiateStandardWithdrawal(msg.sender, _token, _shares);
    }

    function _redeemShares(
        address _token,
        uint256 numShares,
        bool isMax
    ) internal {
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        // This handles the null case when depositReceipt.round = 0
        // Because we start with round = 1 at `initialize`
        uint256 currentRound = vaults[_token].round;

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            ICRERC20(cruizeTokens[_token]).decimals()
        );

        numShares = isMax ? unredeemedShares : numShares;
        if (numShares == 0) {
            return;
        }
        require(numShares <= unredeemedShares, "Exceeds available");

        // If we have a depositReceipt on the same round, BUT we have some unredeemed shares
        // we debit from the unredeemedShares, but leave the amount field intact
        // If the round has past, with no new deposits, we just zero it out for new deposits.
        if (depositReceipt.round < currentRound) {
            depositReceipts[msg.sender][_token].amount = 0;
        }

        // ShareMath.assertUint128(numShares);
        depositReceipts[msg.sender][_token].unredeemedShares = uint128(
            unredeemedShares.sub(numShares)
        );

        IERC20(cruizeTokens[_token]).transfer(msg.sender, numShares);
    }

    /**
     * @notice This function will be called after round completion
     * and transfer the amount which is requested by user in the previous
     * round by calling intiateWithdraw.
     * @param _token withdrawal token address.
     */
    function _completeStandardWithdrawal(address _token) internal {
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][_token];
        Types.VaultState storage vaultState = vaults[_token];
        uint256 withdrawalShares = withdrawal.shares;
        uint16 withdrawalRound = withdrawal.round;
        uint256 decimals = ICRERC20(cruizeTokens[_token]).decimals();
        uint16 currentRound = vaults[_token].round;
        // This checks if there is a withdrawal
        require(withdrawalShares > 0, "Not initiated");
        require(withdrawalRound < currentRound, "Round not closed");
        withdrawal.shares = 0;
        vaultState.queuedWithdrawShares = uint128(
            uint256(vaultState.queuedWithdrawShares).sub(withdrawalShares)
        );
        uint256 withdrawAmount = ShareMath.sharesToAsset(
            withdrawalShares,
            roundPricePerShare[_token][withdrawalRound],
            decimals
        );
        lastQueuedWithdrawAmounts[_token] = lastQueuedWithdrawAmounts[_token]
            .sub(withdrawAmount);
        ICRERC20(cruizeTokens[_token]).burn(msg.sender, withdrawalShares);
        _transferHelper(_token, msg.sender, withdrawAmount);
        emit completeStandardWithdrawal(msg.sender, withdrawAmount, _token);
    }

    /**
     * @notice This function will be use for creating deposit
     * receipts.
     * @param _token depositing token address.
     * @param _amount user depositing amount.
     */
    function _updateDepositInfo(address _token, uint256 _amount) private {
        Types.VaultState storage vaultState = vaults[_token];
        uint256 currentRound = vaultState.round;
        uint256 decimals = ICRERC20(cruizeTokens[_token]).decimals();

        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[_token][depositReceipt.round],
            decimals
        );

        uint256 depositAmount = _amount;
        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(_amount);
            depositAmount = newAmount;
        }

        ShareMath.assertUint104(depositAmount);

        depositReceipts[msg.sender][_token] = Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount),
            unredeemedShares: uint128(unredeemedShares)
        });

        uint256 newTotalPending = uint256(vaultState.totalPending).add(_amount);
        ShareMath.assertUint128(newTotalPending);

        vaultState.totalPending = uint128(newTotalPending);
    }

    /**
     * @notice This function will be responsible for transfer token/ETH
     * the recipent address.
     * @param _token depositing token address.
     * @param _receiver recipient address.
     * @param _amount withdrawal amount.
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

        IAvatar(gnosisSafe).execTransactionFromModule(
            module,
            0,
            _data,
            Enum.Operation.DelegateCall
        );
    }

    /**
     * @notice This function will be called by Gnosis Safe
     * using delegatecall to transfer amount from gnosis safe
     * to receiver address.
     * @param _paymentToken withdrawal token address.
     * @param _receiver recipient address.
     * @param _amount withdrawal amount.
     */
    function transferFromSafe(
        address _paymentToken,
        address _receiver,
        uint256 _amount
    ) external onlyModule nonReentrant {
        // require(msg.sender == module, "not Authorized");
        if (_paymentToken == ETH) {
            (bool sent, ) = _receiver.call{value: _amount}("");
            require(sent, "failed to sent ether");
            return;
        }
        IERC20(_paymentToken).safeTransfer(_receiver, _amount);
    }

    /**
     * @notice This function will be responsible for closing current
     * round.
     * @param _token token address.
     */
    function _closeRound(
        address _token,
        uint256 lastQueuedWithdrawAmount,
        uint256 currentQueuedWithdrawShares
    ) internal returns (uint256 lockedBalance, uint256 queuedWithdrawAmount) {
        uint256 mintShares;
        uint256 totalVaultFee;

        Types.VaultState storage vaultState = vaults[_token];

        uint256 newPricePerShare;
        (
            lockedBalance,
            queuedWithdrawAmount,
            newPricePerShare,
            mintShares,
            totalVaultFee
        ) = calculateSharePrice(
            _token,
            Types.CloseParams(
                ICRERC20(cruizeTokens[_token]).decimals(),
                totalBalance(_token),
                totalSupply(_token),
                lastQueuedWithdrawAmount,
                managementFee,
                currentQueuedWithdrawShares
            )
        );

        // Finalize the pricePerShare at the end of the round
        uint16 currentRound = vaultState.round;
        roundPricePerShare[_token][currentRound] = newPricePerShare;
        vaultState.totalPending = 0;
        vaultState.round = uint16(currentRound + 1);

        // _mint(address(this), mintShares);
        ICRERC20(cruizeTokens[_token]).mint(address(this), mintShares);

        if (totalVaultFee > 0) {
            _transferHelper(_token, payable(feeRecipient), totalVaultFee);
        }
        emit CloseRound(_token, currentRound, newPricePerShare, lockedBalance);
        return (lockedBalance, queuedWithdrawAmount);
    }

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

        // {
        (totalVaultFee) = getVaultFees(
            currentBalance,
            pendingAmount,
            lastLockedAmount
        );
        // }

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

    function getVaultFees(
        uint256 totalTokenBalance,
        uint256 pendingAmount,
        uint256 lastLockedAmount
    ) private view returns (uint256 vaultFee) {
        uint256 roundBalanceWithAPY = totalTokenBalance.sub(pendingAmount);
        uint256 roundApy = roundBalanceWithAPY.sub(lastLockedAmount);
        vaultFee = roundApy.mul(managementFee).div(10**18).div(100);
    }

    function totalBalance(address token) private view returns (uint256) {
        if (token == ETH) return gnosisSafe.balance;
        else return ICRERC20(token).balanceOf(gnosisSafe);
    }

    function totalSupply(address token) private view returns (uint256) {
        return ICRERC20(cruizeTokens[token]).totalSupply();
    }

    function shareBalances(address token, address account)
        public
        view
        returns (uint256 heldByAccount, uint256 heldByVault)
    {
        Types.DepositReceipt memory depositReceipt = depositReceipts[account][
            token
        ];

        if (depositReceipt.round < ShareMath.PLACEHOLDER_UINT) {
            return (balanceOf(token, account), 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            vaults[token].round,
            roundPricePerShare[token][depositReceipt.round],
            ICRERC20(cruizeTokens[token]).decimals()
        );

        return (balanceOf(token, account), unredeemedShares);
    }

    function balanceOf(address token, address account)
        public
        view
        returns (uint256)
    {
        return ICRERC20(cruizeTokens[token]).balanceOf(account);
    }

    function priceOfRound(address token, uint16 round)
        private
        view
        returns (uint256)
    {
        if (round < 2) return 1e18;
        return roundPricePerShare[token][round];
    }

    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        require(feeRecipient_ != address(0));
        feeRecipient = feeRecipient_;
    }

    function setManagementFee(uint256 managementFee_) external onlyOwner {
        require(managementFee_ > 0);
        managementFee = managementFee_;
    }

    function getManagementFee() external view onlyOwner returns (uint256) {
        return managementFee;
    }

    function getFeeRecipient() external view onlyOwner returns (address) {
        return feeRecipient;
    }

    function setCap(uint256 newCap, address token) external onlyOwner {
        require(newCap > 0, "!newCap");
        ShareMath.assertUint104(newCap);
        Types.VaultState storage vault = vaults[token];
        vault.cap = uint104(newCap);
        emit CapSet(vault.cap, newCap);
    }

    function totalTokenPending(address token) external view returns (uint256) {
        Types.VaultState memory vault = vaults[token];
        return vault.totalPending;
    }
}

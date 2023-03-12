// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;
import "../libraries/Types.sol";

abstract contract CruizeStorage {
    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/

    /// @notice Fee recipient for the management fees
    address public feeRecipient;
    /// @notice Performance fee charged on premiums earned in rollToNextOption. Only charged when there is no loss.
    uint256 public performanceFee;
    bool public isPerformanceFeeEnabled;
    /// @notice Management fee charged on entire AUM in rollToNextOption. Only charged when there is no loss.
    uint256 public managementFee;
    bool public isManagementFeeEnable;
    /// @notice role in charge of weekly vault operations such as transfer fund and burn tokens
    address public module;

    /// @notice gnosis safe address where all the fund will be locked
    address public gnosisSafe;
    /// @notice gnosis safe address where all the fund will be locked
    address public cruizeProxy;
    /// @notice crContract address that will be used to create new crcontract clone
    address public crContract;
    /// @notice ETH 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // Fees are 18-decimal places. For example: 20 * 10**18 = 20%
    uint256 internal constant FEE_MULTIPLIER = 10 ** 18;
    // Number of weeks per year = 52.142857 weeks * FEE_MULTIPLIER = 52142857
    // Dividing by weeks per year requires doing num.mul(FEE_MULTIPLIER).div(WEEKS_PER_YEAR)
    /// @notice deprecated
    uint256 internal constant WEEKS_PER_YEAR = 52.142857 ether;

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
    address[] public tokens;

    uint256 internal ROUND_PER_YEAR = 52.142857 ether;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __cruize_gap;
}

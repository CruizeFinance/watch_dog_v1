pragma solidity =0.8.6;
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ICRERC20.sol";
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
contract CruizeVault is ReentrancyGuardUpgradeable, Module {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeMath for uint128;

    //----------------------------//
    //     State Vairable         //
    //----------------------------//
    address immutable module;
    address immutable vault;
    address immutable crContract;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    //----------------------------//
    //        Mappings            //
    //----------------------------//
    mapping(address => address) public cruizeTokens;
    mapping(address => Types.VaultState) public vaults;
    mapping(address => uint128) public currentQueuedWithdrawalAmounts;
    mapping(address => mapping(address => Types.Withdrawal)) public withdrawals;
    mapping(address => mapping(address => Types.DepositReceipt))
        public depositReceipts;

    //----------------------------//
    //        Events              //
    //----------------------------//
    event CreateToken(
        address indexed tokenAddress,
        string tokenName,
        string tokenSymbol,
        uint8 decimal
    );
    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event InstantWithdraw(
        address indexed account,
        uint256 amount,
        uint256 currentRound
    );
    event InitiateWithdrawal(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event CloseRound(
        address indexed token,
        uint128 indexed round,
        uint256 lockedAmount
    );
  

    receive() external payable {
        
        revert();
    }

    constructor(
        address _owner,
        address _vault,
        address _crContract
    ) {
        vault = _vault;
        crContract = _crContract;
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

    /**
     * @notice This function will handle ETH deposits and.
     * mint crTokens against the deposited amount in 1:1.
     * @param _amount user depositing amount.
     */
    function _depositETH(uint256 _amount) internal  {
        if (_amount == 0) revert ZeroAmount(_amount);
        require(msg.value >= _amount);
        _depositFor(ETH, _amount);
        ICRERC20(cruizeTokens[ETH]).mint(msg.sender, _amount);
        (bool sent, ) = vault.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice This function will handle ERC20 deposits and.
     * mint crTokens against the deposited amount in 1:1.
     * @param _token depositing token address.
     * @param _amount user depositing amount.
     */
    function _depositERC20(address _token, uint256 _amount)
        internal
        
    {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        _depositFor(_token, _amount);
        ICRERC20(cruizeTokens[_token]).mint(msg.sender, _amount);
        require(ICRERC20(_token).transferFrom(msg.sender, vault, _amount));
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice This function will handle instant withdrawals.
     * i.e if user deposit in 100 round and want to withdraw
     * in the same round then "withdrawInstantly" with transfer
     * user funds from Gnosis Safe to user address.
     * @param _to Gnosis Safe address.
     * @param _amount user withdrawal amount.
     * @param _token withdrawal token address.
     */
    function _withdrawInstantly(
        address _to,
        uint256 _amount,
        address _token
    ) internal  {
        if (_to != vault) revert InvalidVaultAddress(_to);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        uint256 currentRound = vaults[_token].round;
        if (depositReceipt.round != currentRound)
            revert InvalidWithdrawalRound(depositReceipt.round, currentRound);
        uint256 receiptAmount = depositReceipt.amount;
        if (_amount > receiptAmount)
            revert NotEnoughWithdrawalBalance(receiptAmount, _amount);

        depositReceipt.amount = uint104(receiptAmount.sub(_amount));
        _transferFromGnosis(_to, _token, msg.sender, _amount);
        emit InstantWithdraw(msg.sender, _amount, currentRound);
    }

    /**
     * @notice This function will initiate withdrawal request during locking period
     * of user asset in the specific strategy, so after strategy completion user can
     * can claim his withdrawal request amount from the protocol.
     * @param _amount user withdrawal amount.
     * @param _token withdrawal token address.
     */
    function _initiateWithdraw(uint256 _amount, address _token)
        internal
        
    {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        uint256 currentRound = vaults[_token].round;
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        if (currentRound == depositReceipt.round)
            revert InvalidWithdrawalRound(depositReceipt.round, currentRound);
         uint256 lockedAmount = getLockedAmount(
                msg.sender,
                _token,
                currentRound,
                depositReceipt.round
            );
        if (
            _amount > depositReceipt.amount &&
            _amount > lockedAmount
            
        ) revert NotEnoughWithdrawalBalance(lockedAmount, _amount);
        Types.Withdrawal storage userWithdrawal = withdrawals[msg.sender][
            _token
        ];
        uint256 existingWithdrawalAmount = uint256(userWithdrawal.amount);
        uint256 withdrawalAmount;
        if (userWithdrawal.round == currentRound) {
            withdrawalAmount = existingWithdrawalAmount.add(_amount);
        } else {
            if (existingWithdrawalAmount != 0)
                revert WithdrawalAlreadyExists(existingWithdrawalAmount);
            withdrawalAmount = _amount;
            userWithdrawal.round = uint16(currentRound);
        }
        uint256 currentQueuedWithdrawalAmount = currentQueuedWithdrawalAmounts[
            _token
        ];
        currentQueuedWithdrawalAmounts[_token] = (
            currentQueuedWithdrawalAmount.add(_amount)
        ).toUint128();

        userWithdrawal.amount = uint128(withdrawalAmount);
        emit InitiateWithdrawal(msg.sender, _token, _amount);
    }

    /**
     * @notice This function will be called after round completion
     * and transfer the amount which is requested by user in the previous
     * round by calling intiateWithdraw.
     * @param _token withdrawal token address.
     * @param _to Gnosis Safe address.
     * @param _data will contain encoded (receiver , amount).
     */
    function _completeWithdrawal(
        address _token,
        address _to,
        bytes memory _data
    ) internal  returns (bool success) {
         
        if (_to != vault) revert InvalidVaultAddress(_to);
        Types.Withdrawal storage userQueuedWithdrawal = withdrawals[msg.sender][
            _token
        ];
        uint256 currentRound = vaults[_token].round;
        require(_data.length > 0, "NULL DATA");
        // TODO :: check if data is null
        (address receiver, uint256 amount) = abi.decode(
            _data,
            (address, uint256)
        );
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (receiver == address(0)) revert ZeroAddress(receiver);
        if (amount == 0) revert ZeroAmount(amount);
        if (currentRound == userQueuedWithdrawal.round)
            revert InvalidWithdrawalRound(
                userQueuedWithdrawal.round,
                currentRound
            );
        if (amount > userQueuedWithdrawal.amount)
            revert NotEnoughWithdrawalBalance(
                userQueuedWithdrawal.amount,
                amount
            );

        userQueuedWithdrawal.amount = (
            uint256(userQueuedWithdrawal.amount).sub(amount)
        ).toUint128();
        Types.VaultState storage tokenQueuedWithdrawal = vaults[_token];
        uint256 tokenQueuedWithdrawalAmount = tokenQueuedWithdrawal
            .queuedWithdrawalAmount;

        tokenQueuedWithdrawal.queuedWithdrawalAmount = uint128(
            tokenQueuedWithdrawalAmount.sub(amount)
        );
         success = _transferFromGnosis(_to, _token, receiver, amount);
        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice This function will be use for creating deposit
     * receipts.
     * @param _token depositing token address.
     * @param _amount user depositing amount.
     */
    function _depositFor(address _token, uint256 _amount)  private {
        uint256 currentRound = vaults[_token].round;

        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        uint256 depositAmount = _amount;

        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(_amount);
            depositAmount = newAmount;
        }
     
        uint256 lockedAmount = getLockedAmount(
            msg.sender,
            _token,
            currentRound,
            depositReceipt.round
        );
       
        depositReceipts[msg.sender][_token] = Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount),
            lockedAmount: uint104(lockedAmount)
        });
    }

    /**
     * @notice This function will be responsible for transfer token/ETH
     * the recipent address.
     * @param _to Safe Gnosis address.
     * @param _token depositing token address.
     * @param _receiver recipient address.
     * @param _amount withdrawal amount.
     */
    function _transferFromGnosis(
        address _to,
        address _token,
        address _receiver,
        uint256 _amount
    )  private returns (bool success) {
        
        ICRERC20 crtoken = ICRERC20(cruizeTokens[_token]);
        crtoken.burn(_receiver, _amount);
        bytes memory _data = abi.encodeWithSignature(
            "_transfer(address,address,uint256)",
            _token,
            _receiver,
            _amount
        );

        success = IAvatar(vault).execTransactionFromModule(
            _to,
            0,
            _data,
            Enum.Operation.DelegateCall
        );
        return success;
    }

    /**
     * @notice This function will be called by Gnosis Safe
     * using delegatecall to transfer amount from gnosis safe
     * to receiver address.
     * @param _paymentToken withdrawal token address.
     * @param _receiver recipient address.
     * @param _amount withdrawal amount.
     */
    function _transfer(
        address _paymentToken,
        address _receiver,
        uint256 _amount
    ) nonReentrant external {
        require(msg.sender == module, "not Authorized");
       
        if (_paymentToken == ETH) {

            (bool sent, ) = _receiver.call{value: _amount}("");
            require(sent, "Failed to send Ether");
        } else {
            require(ICRERC20(_paymentToken).transfer(_receiver, _amount));
        }
    }

    /**
     * @notice This function will be responsible for closing current
     * round.
     * @param _token token address.
     */
    function _closeRound(address _token)  internal {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        uint256 currentRound = vaults[_token].round;
        uint256 currentQueuedWithdrawalAmount = currentQueuedWithdrawalAmounts[
            _token
        ];
        Types.VaultState storage tokenVaultState = vaults[_token];
        uint256 totalQueuedWithdrawal = tokenVaultState.queuedWithdrawalAmount;
        totalQueuedWithdrawal = totalQueuedWithdrawal.add(
            currentQueuedWithdrawalAmount
        );
        uint256 totalAmount = totalBalance(_token);
        uint256 lockedAmount = totalAmount.sub(totalQueuedWithdrawal);
        tokenVaultState.lockedAmount = uint104(lockedAmount);
        tokenVaultState.round = uint16(currentRound + 1);
        currentQueuedWithdrawalAmounts[_token] = 0;
        tokenVaultState.queuedWithdrawalAmount = totalQueuedWithdrawal
            .toUint128();

        emit CloseRound(_token, tokenVaultState.round, lockedAmount);
    }

    function getLockedAmount(
        address user,
        address token,
        uint256 currentRound,
        uint256 depositReceiptRound
    ) private view returns (uint104) {
        Types.DepositReceipt memory depositReceipt =
        depositReceipts[user][token];

        if (currentRound > depositReceiptRound)
            return 
            depositReceipt.amount + depositReceipt.lockedAmount;

        return depositReceipt.lockedAmount;
    }

    function totalBalance(address token) private returns (uint256) {
        if (token == ETH) return vault.balance;
        else return ICRERC20(token).balanceOf(vault);
    }
}

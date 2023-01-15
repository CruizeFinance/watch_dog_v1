pragma solidity =0.8.6;
import "../base/Proxy.sol";
import "hardhat/console.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ICRERC20.sol";
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract CruizeVault is ReentrancyGuardUpgradeable, Module {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeMath for uint128;
    /// @notice 7 day period between each options sale.
    uint256 public constant PERIOD = 7 days;
    // Number of weeks per year = 52.142857 weeks * FEE_MULTIPLIER = 52142857
    // Dividing by weeks per year requires doing num.mul(FEE_MULTIPLIER).div(WEEKS_PER_YEAR)
    uint256 private constant WEEKS_PER_YEAR = 52142857;

    address immutable module;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address immutable vault;
    address immutable crContract;
    mapping(address => address) public cruizeTokens;
    /* user address -->  token address --> depositReceipt */
    mapping(address => mapping(address => Types.DepositReceipt))
        public depositReceipts;
    mapping(address => mapping(address => Types.Withdrawal)) public withdrawals;
    //     represent the current queued withdrawal amount of tokens  for  the closing round .
    mapping(address => uint128) currentQueuedWithdrawalAmounts;
    mapping(address => Types.VaultState) public vaults;

    event CreateToken(
        address indexed _tokenAddress,
        string _tokenName,
        string _tokenSymbol,
        uint8 _decimal
    );

    event Deposit(address indexed _account, uint256 _amount);
    event Wthdrawal(address indexed _account, uint _amount);
    event InstantWithdraw(
        address indexed _account,
        uint _amount,
        uint currentRound
    );

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

    function _depositETH(uint256 _amount) internal nonReentrant {
        if (_amount == 0) revert ZeroAmount(_amount);
        require(msg.value >= _amount);
        (bool sent, ) = vault.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        _depositFor(ETH, _amount);
        ICRERC20(cruizeTokens[ETH]).mint(msg.sender, _amount);
        emit Deposit(msg.sender, _amount);
    }

    function _depositERC20(address _token, uint256 _amount)
        internal
        nonReentrant
    {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        _depositFor(_token, _amount);
        require(ICRERC20(_token).transferFrom(msg.sender, vault, _amount));
        ICRERC20(cruizeTokens[_token]).mint(msg.sender, _amount);
        emit Deposit(msg.sender, _amount);
    }

    function _withdrawInstantly(
        address to,
        uint256 amount,
        address token

    ) internal nonReentrant {
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][token];
        uint256 currentRound = vaults[token].round;
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        if (amount == 0) revert ZeroAmount(amount);
      
        if (depositReceipt.round != currentRound)
            revert InvalidWithdrawalRound(depositReceipt.round,currentRound);
        uint256 receiptAmount = depositReceipt.amount;
        if (amount > receiptAmount)
            revert NotEnoughWithdrawalBalance(receiptAmount,amount);
        // Subtraction underflow checks already ensure it is smaller than uint104
        depositReceipt.amount = uint104(receiptAmount.sub(amount));
        _transferFromGnosis(to, token, msg.sender, amount);
        emit InstantWithdraw(msg.sender, amount, currentRound);
    }

    function _initiateWithdraw(uint256 amount, address token)
        internal
        nonReentrant
    {
        if (token == address(0)) revert ZeroAddress(token);
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        if (amount == 0) revert ZeroAmount(amount);
        // require(
        //     depositReceipts[msg.sender][token].amount > 0 ||
        //         depositReceipts[msg.sender][token].lockedAmount > 0,"NOT ENOUGH BALANCE"
        // );
        require(
            depositReceipts[msg.sender][token].amount >= amount ||
                depositReceipts[msg.sender][token].lockedAmount >= amount,
            "NOT ENOUGH TOKEN BALANCE"
        );
        // This caches the `round` variable used in shareBalances
        uint256 currentRound = vaults[token].round;
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][token];
        bool withdrawalIsSameRound = withdrawal.round == currentRound;
        uint256 existingShares = uint256(withdrawal.amount);
        uint256 withdrawalAmount;
        if (withdrawalIsSameRound) {
            withdrawalAmount = existingShares.add(amount);
        } else {
            require(existingShares == 0, "Existing withdraw");
            withdrawalAmount = amount;
            withdrawals[msg.sender][token].round = uint16(currentRound);
        }
        uint256 currentQueuedWithdrawalAmount = currentQueuedWithdrawalAmounts[
            token
        ];
        currentQueuedWithdrawalAmounts[token] = (
            currentQueuedWithdrawalAmount.add(amount)
        ).toUint128();

        withdrawals[msg.sender][token].amount = uint128(withdrawalAmount);
    }

    // user has an withdrawal request
    //  deposited amount >=  withdrawal amount
    // and round must be overed for the withdrawal request .

    function _completeWithdrawal(
        address _token,
        address _to,
        bytes memory _data
    ) internal nonReentrant returns (bool success) {
        if (_to == address(0)) revert ZeroAddress(_to);
        Types.Withdrawal storage userQueuedWithdrawal = withdrawals[msg.sender][
            _token
        ];
        uint256 currentRound = vaults[_token].round;
        require(bytes(_data).length > 0, "NULL DATA");
        // TODO :: check if data is null
        (address token, address receiver, uint256 amount) = abi.decode(
            _data,
            (address, address, uint256)
        );
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        if (receiver == address(0)) revert ZeroAddress(receiver);
        if (amount == 0) revert ZeroAmount(amount);
         if (currentRound == userQueuedWithdrawal.round)
            revert InvalidWithdrawalRound(userQueuedWithdrawal.round,currentRound);
            
     //         require(queueWithdrawal.round < currentRound );
        if (amount > userQueuedWithdrawal.amount)
            revert NotEnoughWithdrawalBalance(userQueuedWithdrawal.amount,amount);
        //          require(queueWithdrawal.amount >=  amount  );
       
    

        success = _transferFromGnosis(_to, token, receiver, amount);
   

        userQueuedWithdrawal.amount = (
            uint256(userQueuedWithdrawal.amount).sub(amount)
        ).toUint128();
        uint256 tokenQueuedWithdrawalAmount = vaults[_token]
            .queuedWithdrawalAmount;
        
        vaults[_token].queuedWithdrawalAmount = uint128(
            tokenQueuedWithdrawalAmount.sub(amount)
        );
        emit Wthdrawal(msg.sender, amount);
    }

    function _depositFor(address token, uint256 amount) private {
        uint256 currentRound = vaults[token].round;

        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][token];
        uint256 depositAmount = amount;

        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(amount);
            depositAmount = newAmount;
        }
        uint256 lockedAmount = getLockedAmount(msg.sender, token);
        depositReceipts[msg.sender][token] = Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount),
            lockedAmount: uint104(lockedAmount)
        });
    }

    function _transferFromGnosis(
        address _to,
        address _token,
        address _receiver,
        uint256 _amount
    ) private returns (bool success) {
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

    function _transfer(
        address paymentToken,
        address receiver,
        uint256 amount
    ) external {
        require(msg.sender == module, "not Authorized");
        console.log("in FUNCTION TRANSFER");
        if (paymentToken == ETH) {
            console.log('before::',msg.sender.balance);
            (bool sent, ) = receiver.call{value: amount}("");
            console.log('after::',msg.sender.balance);
            require(sent, "Failed to send Ether");
        } else {
            ICRERC20(paymentToken).transfer(receiver, amount);
        }
    }

    function _closeRound(address token) internal nonReentrant onlyOwner {
        if (token == address(0)) revert ZeroAddress(token);
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        uint256 currentRound = vaults[token].round;
        uint256 currentQueuedWithdrawalAmount = currentQueuedWithdrawalAmounts[
            token
        ];
        uint256 totalQueuedWithdrawal = vaults[token].queuedWithdrawalAmount;
        totalQueuedWithdrawal = totalQueuedWithdrawal.add(
            currentQueuedWithdrawalAmount
        );
        uint256 totalAmount = totalBalance(token);
        uint256 lockedAmount = totalAmount.sub(totalQueuedWithdrawal);
        vaults[token].lockedAmount = uint104(lockedAmount);
        vaults[token].round = uint16(currentRound + 1);
        currentQueuedWithdrawalAmounts[token] = 0;
        vaults[token].queuedWithdrawalAmount = totalQueuedWithdrawal
            .toUint128();

        //     Todo :: emit an event for last lockedAmount.
    }

    function getLockedAmount(address user, address token)
        private
        view
        returns (uint104)
    {
        // currentRound > prevRound
        if (vaults[token].round > depositReceipts[user][token].round) {
           
            return depositReceipts[user][token].amount;
        }
        return depositReceipts[user][token].lockedAmount;
    }

    function totalBalance(address token) private returns (uint256) {
        if (token == ETH) return vault.balance;
        else return ICRERC20(token).balanceOf(vault);
    }
}

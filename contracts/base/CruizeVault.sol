pragma solidity =0.8.6;
import "../base/Proxy.sol";
import "hardhat/console.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ICRERC20.sol";
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract CruizeVault is ReentrancyGuardUpgradeable ,Module {
    using SafeMath for uint256;
        /// @notice 7 day period between each options sale.
    uint256 public constant PERIOD = 7 days;
    // Number of weeks per year = 52.142857 weeks * FEE_MULTIPLIER = 52142857
    // Dividing by weeks per year requires doing num.mul(FEE_MULTIPLIER).div(WEEKS_PER_YEAR)
    uint256 private constant WEEKS_PER_YEAR = 52142857;

    address immutable module;
    address constant ETH = 0x0000000000000000000000000000000000000000;
    address immutable  vault;
    address immutable  crContract;
    mapping(address => address) public cruizeTokens;
    /* user address -->  token address --> depositReceipt */
    mapping(address => mapping( address=> Types.DepositReceipt )) public depositReceipts;
    mapping(address =>mapping( address=>Types.Withdrawal ) ) public withdrawals;
    mapping(address =>Types.VaultState )  public vaults;

/**
 * mapping(address => bool) withdrawRequest;
 * create a function to initiate withdrawal request.
 * now user can withdraw  from here and burn user's token.
*/
    event CreateToken(
        address indexed _tokenAddress,
        string _tokenName,
        string _tokenSymbol,
        uint8 _decimal
    );

    event Deposit(address indexed _account, uint256 _amount);
    event Wthdrawal(address indexed _account, uint _amount);

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
    //     Mutation Functions     //
    //----------------------------//

    /// @param initializeParams Parameters of initialization encoded
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
    /**
    * case-1: if user is depositing in the first round
    * 
    */
    function depositETH(uint256 _amount) nonReentrant internal  {
        if (_amount == 0) revert ZeroAmount(_amount);
        (bool sent,) = vault.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        _depositFor(ETH,_amount);
        ICRERC20(cruizeTokens[ETH]).mint(msg.sender, _amount);
        emit Deposit(msg.sender, _amount);
    }

    function depositERC20(address _token, uint256 _amount) nonReentrant internal {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        _depositFor(_token,_amount);
        require(ICRERC20(_token).transferFrom(msg.sender, vault, _amount));
        ICRERC20(cruizeTokens[_token]).mint(msg.sender, _amount);
    }
/**
1 update vaults state
 1.1 update lockedAmount set zero
 1.2 update lastLockedAmount

2 . calculate queuedWithdrawalAmount.
3 calculate lockedAmount for the next round. totalDeposit - withdrawalAmount
4 update the round
*/

function closeRound(address token) public onlyOwner {
     uint256 currentRound = vaults[token].round;

//     TODO :: calculate queuedWithdrawal Amount .

    uint256 queuedWithdrawalAmount  = 0;


    uint256 totalAmount = totalBalance(token);

    uint256 lockedAmount = totalAmount.sub(queuedWithdrawalAmount);

     vaults[token].lockedAmount =uint104( lockedAmount );

     vaults[token].round = uint16(currentRound + 1);

     vaults[token].queuedWithdrawalAmount = 0;

//     Todo :: emit an event for last lockedAmount.


}



    function totalBalance (address token)  private returns(uint256){
        if (token == ETH) return  vault.balance;

        else return ICRERC20(token).balanceOf(vault);

    }

   /**
     * @notice Mints the vault shares to the creditor
     * @param token is the amount of `asset` deposited
     * @param amount is the address to receive the deposit
     */
    function _depositFor(address token,uint256 amount) private {
        uint256 currentRound = vaults[token].round;

        Types.DepositReceipt memory depositReceipt = depositReceipts[msg.sender][token];
        uint256 depositAmount = amount;


        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(amount);
            depositAmount = newAmount;
        }
         uint256  lockedAmount = getLockedAmount(msg.sender,token);
        console.log("locked amount",lockedAmount);
        depositReceipts[msg.sender][token] = Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount),
            lockedAmount: uint104(lockedAmount)
        });
// Todo :: emit events  for depositAmount.


    }

function getLockedAmount(address user, address token) private returns(uint104 )
    {
        // currentRound > prevRound
        if(vaults[token].round > depositReceipts[user][token].round){
            console.log("round different");
           return  depositReceipts[user][token].amount;
        }

            console.log("round same");
          return depositReceipts[user][token].lockedAmount;
    }



    function completeWithdrawal(
        address _to,
        bytes memory _data
    ) internal nonReentrant returns (bool success) {
        if (_to == address(0)) revert ZeroAddress(_to);
        // check if data is null 
        (address token, address receiver, uint amount) = abi.decode(
            _data,
            (address, address, uint256)
        );
        if (cruizeTokens[token] == address(0)) revert AssetNotAllowed(token);
        if (receiver == address(0)) revert ZeroAddress(receiver);
        if (amount == 0) revert ZeroAmount(amount);

        success = _transferFromGnosis(_to,_data);
        emit Wthdrawal(msg.sender, amount);
    }

    function _transferFromGnosis(
        address _to,
        address _token,
        address _receiver,
       uint256 _amount)private returns (bool success)  {

         ICRERC20 crtoken = ICRERC20(cruizeTokens[token]);
        crtoken.burn(receiver, amount);
        _data = abi.encodeWithSignature(
            "_transfer(address,address,uint256)",
            token,
            receiver,
            amount
        );

//         TODO:: make this 0 and 1 constant .
        success = IAvatar(vault).execTransactionFromModule(
            _to,
            0,
            _data,
            1
        );
        return success;
    }
    function _transfer(
        address paymentToken,
        address receiver,
        uint256 amount
    ) external {
        require(msg.sender == module,"");
        if (paymentToken == ETH) {
            
            (bool sent,) = receiver.call{value: amount}("");
            require(sent, "Failed to send Ether");
             
        } else {
            ICRERC20(paymentToken).transfer(receiver, amount);
        }
    }

    /**
     * @notice Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`
     * @param amount is the amount to withdraw
     */

    function withdrawInstantly(address to,uint256 amount,address token) external nonReentrant {
        Types.DepositReceipt storage depositReceipt =
            depositReceipts[msg.sender][token];

        uint256 currentRound = vaults[token].round;
        if (_amount == 0) revert ZeroAmount(_amount);
//         TODO :: make custom revert .
        require(depositReceipt.round == currentRound, "Invalid round");

        uint256 receiptAmount = depositReceipt.amount;
        //         TODO :: make custom revert .
        require(receiptAmount >= amount, "Exceed amount");

        // Subtraction underflow checks already ensure it is smaller than uint104
        depositReceipt.amount = uint104(receiptAmount.sub(amount));

//        emit InstantWithdraw(msg.sender, amount, currentRound);

        _transferFromGnosis(to,token,msg.sender, amount);
    }

}


// to = Module
// user -> CruizeContract -> Safe ->  DELLEGATECALL(Module).Withdraw -> Safe

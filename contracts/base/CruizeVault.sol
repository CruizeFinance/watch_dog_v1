pragma solidity =0.8.6;
import "../base/Proxy.sol";
import "hardhat/console.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ICRERC20.sol";
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
contract CruizeVault is ReentrancyGuardUpgradeable ,Module {
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
    mapping(address => address => Types.DepositReceipt) public depositReceipts;
    mapping(address => address => Types.Withdrawal )  public withdrawals;
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

        uint256 currentRound = vaults[ETH].round;
        Types.DepositReceipt memory receipt = depositReceipts[msg.sender];
        uint256 depositAmount = amount;

        if(currentRound == receipt.round){
            uint256 newAmount = uint256(receipt.amount).add(amount);
            depositAmount = newAmount;
        }

        depositReceipts[msg.sender] = Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount),
            lockedAmount: uint128(0)
        });

        ICRERC20(cruizeTokens[ETH]).mint(msg.sender, _amount);
        emit Deposit(msg.sender, _amount);
    }

    function depositERC20(address _token, uint256 _amount) nonReentrant internal {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (_amount =< 0) revert ZeroAmount(_amount);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        require(token.transferFrom(msg.sender, vault, _amount));
        ICRERC20(cruizeTokens[_token]).mint(msg.sender, _amount);
        depositReceipts[msg.sender][_token].amount.add(uint104(_amount));
        uint16 currentRound = vaults[_token].round;
        depositReceipts[msg.sender][_token].round = currentRound;
        emit Deposit(msg.sender, _amount);
    }

     function initializeWithdrawal() external {
         require(!withdrawalRequest[msg.sender],"request already initiated ");
         withdrawalRequest[msg.sender] =  true;
     }

/**
     * @notice Mints the vault shares to the creditor
     * @param amount is the amount of `asset` deposited
     * @param creditor is the address to receieve the deposit
     */
    function _depositFor(address token,uint256 amount) private {
        uint256 currentRound = vaults.round;

        Types.DepositReceipt memory depositReceipt = depositReceipts[msg.sender][token];

        // If we have an unprocessed pending deposit from the previous rounds, we have to process it.


        uint256 depositAmount = amount;
        uint256 lockedAmount =   0

        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(amount);
            depositAmount = newAmount;
        }
       else {

           lockedAmount = getLockedAmount(msg.sender,token);
    }
        depositReceipts[msg.sender][token]= Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount),
            lockedAmount: uint128(lockedAmount)
        });


    }
 function getLockedAmount(address user, address token) returns(uint256 lockedAmount)
{
 lockedAmount =  uint256 (depositReceipts[user][token].lockedAmount).add(uint256(depositReceipts[user][token].amount));
}




    function completeWithdrawal(
        address _to,
        bytes memory _data,
        Enum.Operation _operation
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
        ICRERC20 crtoken = ICRERC20(cruizeTokens[token]);
        crtoken.burn(receiver, amount);
        _data = abi.encodeWithSignature(
            "_transfer(address,address,uint256)",
            token,
            receiver,
            amount
        );

        success = IAvatar(vault).execTransactionFromModule(
            _to,
            0,
            _data,
            _operation
        );

        emit Wthdrawal(msg.sender, amount);
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


}


// to = Module
// user -> CruizeContract -> Safe ->  DELLEGATECALL(Module).Withdraw -> Safe

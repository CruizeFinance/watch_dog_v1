pragma solidity =0.8.6;
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../libraries/SharesMath.sol";
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
    using ShareMath for Types.DepositReceipt;

    //----------------------------//
    //     State Vairable         //
    //----------------------------//
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
    // token => round => price
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
        uint16 indexed round,
        uint256 SharePerUnit,
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
        gnosisSafe = _vault;
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

    function initRounds(address token, uint256 numRounds)
        external
        nonReentrant
    {
        require(numRounds > 0, "!numRounds");

        uint16 _round = vaults[token].round;

        for (uint16 i = 0; i < numRounds; i++) {
            uint16 index = _round + i;
            require(roundPricePerShare[token][index] == 0, "Initialized"); // AVOID OVERWRITING ACTUAL VALUES
            roundPricePerShare[token][index] = Types.UNIT;
        }
    }

    /**
     * @notice This function will handle ETH deposits and.
     * mint crTokens against the deposited amount in 1:1.
     * @param _amount user depositing amount.
     */
    function _depositETH(uint256 _amount) internal {
        if (_amount == 0) revert ZeroAmount(_amount);
        _depositFor(ETH, _amount);
        ICRERC20(cruizeTokens[ETH]).mint(msg.sender, _amount);
        (bool sent, ) = gnosisSafe.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        emit Deposit(msg.sender, _amount);
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
        _depositFor(_token, _amount);
        ICRERC20(cruizeTokens[_token]).mint(msg.sender, _amount);
        require(ICRERC20(_token).transferFrom(msg.sender, gnosisSafe, _amount));
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice This function will handle instant withdrawals.
     * i.e if user deposit in 100 round and want to withdraw
     * in the same round then "withdrawInstantly" will transfer
     * user funds from Gnosis Safe to user address.
     * @param _amount user withdrawal amount.
     * @param _token withdrawal token address.
     */
    function _withdrawInstantly(uint104 _amount, address _token) internal {
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (_amount == 0) revert ZeroAmount(_amount);
        Types.DepositReceipt storage depositReceipt = depositReceipts[
            msg.sender
        ][_token];
        Types.VaultState storage vaultState = vaults[_token];

        uint16 currentRound = vaultState.round;
        if (depositReceipt.round != currentRound)
            revert InvalidWithdrawalRound(depositReceipt.round, currentRound);
        uint104 receiptAmount = depositReceipt.amount;
        if (_amount > receiptAmount)
            revert NotEnoughWithdrawalBalance(receiptAmount, _amount);

        depositReceipt.amount = receiptAmount - _amount;
        _transferFromGnosis(_token, msg.sender, uint256(_amount));

        vaultState.totalPending = uint128(
            uint256(vaultState.totalPending).sub(_amount)
        );
        emit InstantWithdraw(msg.sender, _amount, currentRound);
    }

    /**
     * @notice This function will initiate withdrawal request during locking period
     * of user asset in the specific strategy, so after strategy completion user can
     * can claim his withdrawal request amount from the protocol.
     * @param _shares user withdrawal amount.
     * @param _token withdrawal token address.
     */
    function _initiateWithdraw(uint256 _shares, address _token) internal {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        if (_shares == 0) revert ZeroAmount(_shares);
        uint256 currentRound = vaults[_token].round;
        uint256 userShares = balanceInShares(msg.sender , _token);
        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];

        if (currentRound == depositReceipt.round)
            revert InvalidWithdrawalRound(depositReceipt.round, currentRound);
      
        if (_shares > userShares)
            revert NotEnoughWithdrawalBalance(0,_shares);
        Types.Withdrawal storage userWithdrawal = withdrawals[msg.sender][
            _token
        ];

        uint256 existingWithdrawalShares = uint256(userWithdrawal.shares);
        uint256 withdrawalShares;

        if (userWithdrawal.round == currentRound) {
            withdrawalShares = existingWithdrawalShares.add(_shares);
        } else {
            if (existingWithdrawalShares != 0)
                revert WithdrawalAlreadyExists(existingWithdrawalShares);
            withdrawalShares = _shares;
            userWithdrawal.round = uint16(currentRound);
            userWithdrawal.shares = uint128(withdrawalShares);
        }

        uint256 currentQueuedWithdrawalShare= currentQueuedWithdrawalShares[
            _token
        ];

        currentQueuedWithdrawalShares[_token] = (
            currentQueuedWithdrawalShare.add(_shares)
        ).toUint128();

        emit InitiateWithdrawal(msg.sender, _token, _shares);
    }

    /**
     * @notice This function will be called after round completion
     * and transfer the amount which is requested by user in the previous
     * round by calling intiateWithdraw.
     * @param _token withdrawal token address.
     */
    function _completeWithdrawal(address _token)
        internal
        returns (bool success)
    {
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);
        Types.Withdrawal storage withdrawal = withdrawals[msg.sender][
            _token
        ];
        Types.VaultState storage vaultState = vaults[_token];
        uint256 withdrawalShares = withdrawal.shares;
        uint16 withdrawalRound = withdrawal.round;
        uint256 decimals =ICRERC20(cruizeTokens[_token]).decimals();


        uint16 currentRound = vaults[_token].round;

        // This checks if there is a withdrawal
        require(withdrawalShares > 0, "Not initiated");

        require(withdrawalRound < currentRound, "Round not closed");

        withdrawal.shares = 0;
        vaultState.queuedWithdrawShares = uint128(
            uint256(vaultState.queuedWithdrawShares).sub(withdrawalShares)
        );

        uint256 withdrawAmount =
            ShareMath.sharesToAsset(
                withdrawalShares,
                roundPricePerShare[_token][withdrawalRound],
                decimals
            );

        lastQueuedWithdrawAmounts[_token] = lastQueuedWithdrawAmounts[_token].sub(withdrawAmount);

        ICRERC20 crtoken = ICRERC20(cruizeTokens[_token]);
        crtoken.burn(msg.sender, withdrawalShares);
        success = _transferFromGnosis(_token, msg.sender, withdrawAmount);
        emit Withdrawal(msg.sender, withdrawAmount);
    }

    /**
     * @notice This function will be use for creating deposit
     * receipts.
     * @param _token depositing token address.
     * @param _amount user depositing amount.
     */
    function _depositFor(address _token, uint256 _amount) private {
        Types.VaultState storage vaultState = vaults[_token];
        uint256 currentRound = vaultState.round;

        Types.DepositReceipt memory depositReceipt = depositReceipts[
            msg.sender
        ][_token];

        uint256 depositAmount = _amount;
        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (currentRound == depositReceipt.round) {
            uint256 newAmount = uint256(depositReceipt.amount).add(_amount);
            depositAmount = newAmount;
        }

        ShareMath.assertUint104(depositAmount);

        depositReceipts[msg.sender][_token] = Types.DepositReceipt({
            round: uint16(currentRound),
            amount: uint104(depositAmount)
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
    function _transferFromGnosis(
        address _token,
        address _receiver,
        uint256 _amount
    ) private returns (bool success) {
        bytes memory _data = abi.encodeWithSignature(
            "TransferFromSafe(address,address,uint256)",
            _token,
            _receiver,
            _amount
        );

        success = IAvatar(gnosisSafe).execTransactionFromModule(
            module,
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
    function TransferFromSafe(
        address _paymentToken,
        address _receiver,
        uint256 _amount
    ) external nonReentrant returns (bool sent) {
        require(msg.sender == module, "not Authorized");
        if (_paymentToken == ETH) {
            (sent, ) = _receiver.call{value: _amount}("");
        } else {
            sent = ICRERC20(_paymentToken).transfer(_receiver, _amount);
        }
    }

    /**
     * @notice This function will be responsible for closing current
     * round.
     * @param _token token address.
     */
    function _closeRound(address _token) internal {
        if (_token == address(0)) revert ZeroAddress(_token);
        if (cruizeTokens[_token] == address(0)) revert AssetNotAllowed(_token);


        Types.VaultState storage vaultState = vaults[_token];
        uint16 currentRound = vaultState.round;

        uint256 currQueuedWithdrawalShares = currentQueuedWithdrawalShares[
            _token
        ];

        // Calculate new "unitPricePerShare" for the current round
        uint256 newSharePerUnit = calculateSharePrice(_token);
        roundPricePerShare[_token][currentRound] = newSharePerUnit;

        // Calculate new "lockedAmount" , queuedWithdrawAmount for the next round
        (uint256 lockedBalance ,uint256 queuedWithdrawAmount) = calculateQueuedWithdrawAmount(_token,newSharePerUnit);
        vaultState.totalPending = 0;
        vaultState.round = uint16(currentRound + 1);
        roundPricePerShare[_token][vaultState.round] = 1e18; // for advance calculation

        lastQueuedWithdrawAmounts[_token] = queuedWithdrawAmount;

        uint256 newQueuedWithdrawShares =
            uint256(vaultState.queuedWithdrawShares).add(
                currQueuedWithdrawalShares
            );
        ShareMath.assertUint128(newQueuedWithdrawShares);
        vaultState.queuedWithdrawShares = uint128(newQueuedWithdrawShares);

        currentQueuedWithdrawalShares[_token] = 0;

        ShareMath.assertUint104(lockedBalance);
        vaultState.lockedAmount = uint104(lockedBalance);

        emit CloseRound(_token, currentRound,  newSharePerUnit,lockedBalance );
    }

    function calculateSharePrice(address _token) private returns(uint256 sharePrice) {
        Types.VaultState memory vaultState = vaults[_token];
        uint256 currentBalance = totalBalance(_token);
        uint256 decimals =ICRERC20(cruizeTokens[_token]).decimals();
        uint256 pendingAmount = currentBalance >  vaultState.totalPending ? vaultState.totalPending : 0; // just to constraint the 1st round
        uint256 lastQueuedWithdrawShares = vaultState.queuedWithdrawShares;
        uint256 lastQueuedWithdrawAmount = lastQueuedWithdrawAmounts[_token];
        uint256 currentShareSupply = ICRERC20(cruizeTokens[_token]).totalSupply();
        uint256 lastRoundPrice = vaultState.round == 1 ? 10**decimals :
          roundPricePerShare[_token][vaultState.round - 1] ;
        uint256 locked = vaultState.round == 1 ? currentBalance : vaultState.lockedAmount ;
        console.log(currentBalance,lastQueuedWithdrawAmount,pendingAmount);
        sharePrice = currentShareSupply != 0 ? ShareMath.pricePerShare(
                    
                currentBalance.sub(lastQueuedWithdrawAmount).sub(pendingAmount),     // subtract last queued withdraw amount from origianl asset balance
                currentShareSupply.sub(lastQueuedWithdrawShares).sub(pendingAmount),
                // ShareMath.sharesToAsset(currentShareSupply.sub(lastQueuedWithdrawShares), lastRoundPrice, decimals).sub(pendingAmount), // subtract queued withdraw shares from total shares
                
                // locked,
                // lastRoundPrice, // sharePerUnit of previous round
                decimals
            ) : 10**decimals;

    }

     function calculateQueuedWithdrawAmount(address _token,uint256 sharePerUnit) private returns(uint256 lockedBalance, uint256 queuedWithdrawAmount) {
        uint256 currentBalance = totalBalance(_token);
        uint256 lastQueuedWithdrawAmount = lastQueuedWithdrawAmounts[_token];
        uint128 currentQueuedWithdrawShares = currentQueuedWithdrawalShares[_token];

         queuedWithdrawAmount = lastQueuedWithdrawAmount.add(
                ShareMath.sharesToAsset(
                    currentQueuedWithdrawShares,
                    sharePerUnit,
                    ICRERC20(cruizeTokens[_token]).decimals()
                )
            );
        console.log("lastQueuedWithdrawAmount::",lastQueuedWithdrawAmount);

            console.log("calculateQueuedWithdrawAmount::queuedWithdrawAmount",queuedWithdrawAmount);
        return (currentBalance.sub(queuedWithdrawAmount),queuedWithdrawAmount);
    }
    
    function totalBalance(address token) private returns (uint256) {
        if (token == ETH) return gnosisSafe.balance;
        else return ICRERC20(token).balanceOf(gnosisSafe);
    }

    // crTokens = ( ( locked - lastDepositAmount) / currentRound_unitPerShare ) + (lastDepsositAmount *(lastRound_unitPershare/ depositTime_unitPershare ) )
    function balanceInShares(address account ,address token) public view returns (uint256) {
        uint256 decimals = ICRERC20(cruizeTokens[token]).decimals();
        uint256 balance = ICRERC20(cruizeTokens[token]).balanceOf(account);
        Types.DepositReceipt memory depositReceipt = depositReceipts[account][token];
        uint256 priceOfLastRound = priceOfRound(token,vaults[token].round-1);
        uint256 priceOfCurrentRound = priceOfRound(token,vaults[token].round);
        uint256 priceOfLastDepositRound = priceOfRound(token,depositReceipt.round);

        uint256 lastShares= ShareMath.assetToShares(depositReceipt.amount, priceOfLastDepositRound, decimals);
        


        uint256 shares = balance.sub(depositReceipt.amount).mul(10**decimals).div(priceOfLastRound);
        // uint256 latestShares = uint256(depositReceipt.amount).mul(10**decimals).div(priceOfLastRound.mul(10**decimals).div(priceOfCurrentRound));
        uint256 latestShares = uint256(depositReceipt.amount).mul(10**decimals).div(priceOfLastRound.mul(10**decimals).div(priceOfLastDepositRound));
        console.log("shares",shares);
        console.log("latestShares",latestShares);
        console.log("totalShares",shares.add(latestShares));
        return shares.add(latestShares);
    }

    function priceOfRound(address token,uint16 round) private view returns(uint256) {
        if(round < 2) return 1e18;
        return roundPricePerShare[token][round];
    }

    function balanceInAsset(address account ,address token) external returns (uint256) {
        uint256 shares = balanceInShares(account,token);
        uint256 decimals = ICRERC20(cruizeTokens[token]).decimals();
        uint256 price = priceOfRound(token,vaults[token].round-1);
        return shares.mul(price).div(10**decimals);
    }
}
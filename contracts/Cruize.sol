pragma solidity =0.8.6;
import "hardhat/console.sol";
import "./base/CruizeVault.sol";
import "./base/Proxy.sol";
contract Cruize is CruizeVault, Proxy {
    constructor(
        address _owner,
        address _vault,
        address _crContract
    ) CruizeVault(_owner, _vault, _crContract) {}

    /**
     * @notice createToken will Clone CRTokenUpgradeable (ERC20 token).
     * @param name name of ERC20Upgradeable Contract.
     * @param symbol symbol of ERC20Upgradeable Contract.
     * @param decimal decimal value of ERC20Upgradeable Contract.
     */

    function createToken(
        string memory name,
        string memory symbol,
        address token,
        uint8 decimal
    ) external onlyOwner {
        if (cruizeTokens[token] != address(0)) revert AssetAlreadyExists(token);
        ICRERC20 crToken = ICRERC20(createClone(crContract));
        cruizeTokens[token] = address(crToken);
        crToken.initialize(name, symbol, decimal);
        vaults[token].round = 1;
        emit CreateToken(address(crToken), name, symbol, decimal);
    }

    /**
     * @notice This function will be use for depositing assets.
     * @param token depositing token address.
     * @param amount user depositing amount.
     */
    function deposit(address token, uint256 amount) nonReentrant  external payable {
        if (token == ETH) {
            _depositETH(msg.value);
        } else {
            _depositERC20(token, amount);
        }
    }

    /**
     * @notice This function will be use for depositing assets.
     * @param token depositing token address.
     * @param to Safe Gnosis address.
     * @param data will contain encoded (receiver , amount).
     */
    function withdraw(
        address token,
        address to,
        bytes memory data
    ) external nonReentrant  {
        _completeWithdrawal(token, to, data);
    }

    /**
     * @notice This function will be use for initiating withdrawal request
     * before the round closing.
     * @param amount withdrawal amount.
     * @param token depositing token address.
     */
    function initiateWithdrawal(uint256 amount, address token)  nonReentrant external {
        _initiateWithdraw(amount, token);
    }

    /**
     * @notice This function will be use for instant withdraws.
     * @param to Gnosis Safe address.
     * @param amount user withdrawal amount.
     * @param token withdrawal token address.
     */
    function withdrawInstantly(
        address to,
        uint104 amount,
        address token
    ) external nonReentrant {
        _withdrawInstantly(to, amount, token);
    }

    /**
     * @notice function closeRound  will be responsible for closing current round.
     * @param token token address.
     */
    function closeRound(address token) external   nonReentrant onlyOwner {
        _closeRound(token);
    }
}
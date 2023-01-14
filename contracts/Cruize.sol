pragma solidity =0.8.6;
import "hardhat/console.sol";
import "./base/CruizeVault.sol";

contract Cruize is CruizeVault, Proxy {
    constructor(
        address _owner,
        address _vault,
        address _crContract
    ) CruizeVault(_owner, _vault, _crContract) {}

    /**
     * @notice createToken  will Clone CRTokenUpgradeable (ERC20 token).
     * @param name name of   ERC20Upgradeable Contract.
     * @param symbol symbol of   ERC20Upgradeable Contract.
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

    function deposit(address token, uint256 amount) external payable {
        if (token == ETH) {
            _depositETH(msg.value);
        } else {
            _depositERC20(token, amount);
        }
    }

    function withdraw(
        address token,
        address to,
        bytes memory data
    ) external {
        _completeWithdrawal(token, to, data);
    }

    function initiateWithdrawal(uint256 amount, address token) external {
        _initiateWithdraw(amount, token);
    }

    function withdrawInstantly(
        address to,
        uint256 amount,
        address token
    ) external {
        _withdrawInstantly(to, amount, token);
    }

    function closeRound(address token) external {
        _closeRound(token);
    }
}

// to = Module
// user -> Vault -> Safe ->  DELLEGATECALL(Module).Withdraw -> Safe

pragma solidity =0.8.6;
import "@gnosis.pm/zodiac/contracts/core/Module.sol";

contract CruizeVault is Module {
address public Vault;
constructor(address _owner, address _vault) {
   bytes memory initializeParams = abi.encode(_owner, _vault);
   setUp(initializeParams);
}

/// @dev Initialize function, will be triggered when a new proxy is deployed
/// @param initializeParams Parameters of initialization encoded
function setUp(bytes memory initializeParams) public override initializer {
   __Ownable_init();
   (address _owner, address _vault) = abi.decode(initializeParams, (address, address));
   Vault = _vault;
   setAvatar(_owner);
   setTarget(_vault);
   transferOwnership(_owner);
}
   function sendmoney(address to,uint256 value,bytes memory data,Enum.Operation operation) external returns(bool success) {
    success  = IAvatar(Vault).execTransactionFromModule(to,value,data,operation);
}
}

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.6;
import "../libraries/Errors.sol";
import "../storage/CruizeStorage.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "hardhat/console.sol";

contract CruizeProxy is CruizeStorage, TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address admin,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, admin, _data) {}
}

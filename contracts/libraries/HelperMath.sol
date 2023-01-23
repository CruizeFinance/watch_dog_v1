
// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";


library HelperMath {
    using SafeMath for uint256;
 
    /************************************************
     *  HELPERS
     ***********************************************/

    function assertUint104(uint256 num) internal pure {
        require(num <= type(uint104).max, "Overflow uint104");
    }

    function assertUint128(uint256 num) internal pure {
        require(num <= type(uint128).max, "Overflow uint128");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.8.6;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Types} from "./Types.sol";
import "hardhat/console.sol";

library ShareMath {
    using SafeMath for uint256;

    uint256 internal constant PLACEHOLDER_UINT = 1;

    function assetToShares(
        uint256 assetAmount,
        uint256 assetPerShare,
        uint256 decimals
    ) internal view returns (uint256) {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");
        return Math.mulDiv(assetAmount,1e18,assetPerShare,Math.Rounding.Up);
    }

    function sharesToAsset(
        uint256 shares,
        uint256 assetPerShare,
        uint256 decimals
    ) internal pure returns (uint256) {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");
        return Math.mulDiv(shares,assetPerShare,1e18,Math.Rounding.Up);

        // return shares.mul(assetPerShare);
    }

    /**
     * @notice Returns the shares unredeemed by the user given their DepositReceipt
     * @param currentRound is the `round` stored on the vault
     * @param amount is the price in asset per share
     * @param assetPerShare is the price in asset per share
     * @param decimals is the price in asset per share
     * @return shares is the user's virtual balance of shares that are owed
     */
    function getSharesFromReceipt(
        uint256 currentRound,
        uint256 amount,
        uint256 assetPerShare,
        uint256 decimals
    ) internal view returns (uint256 shares) {
        if (currentRound == 1) {
               return assetToShares(amount, 10**decimals,decimals);
        }
        return  assetToShares(amount, assetPerShare,decimals);
    }

    function pricePerShare(
        uint256 totalAssets,
        uint256 totalShares,
        uint256 decimals
    ) internal view returns (uint256) {
        uint256 singleShare = 10**decimals;
        // ( AmountAfterStrategy / principle ) * rounds[n-1].UnitPerShare
        console.log("totalAmount",totalAssets);
        console.log("principleAmount",totalShares);

        return Math.mulDiv(totalAssets,singleShare,totalShares,Math.Rounding.Up);
        
        // return totalAmount.mul(lastPricePerUnit).div(principleAmount);
    }

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

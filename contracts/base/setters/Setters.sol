// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;
import "../../libraries/SharesMath.sol";
import "../../libraries/Events.sol";
import "../getters/Getters.sol";

contract Setters is Events, Getters {
    using SafeMath for uint256;

    /************************************************
     *  SETTERS
     ***********************************************/
    /**
     * @notice Sets a new cap for deposits.
     * @param newCap is the new cap for deposits.
     * @param token is the address for which we have to set new cap.
     */
    function setCap(
        address token,
        uint256 newCap
    ) external onlyOwner tokenIsAllowed(token) numberIsNotZero(newCap) {
        uint256 currentTokenBalance = totalBalance(token,0);
        if (newCap < currentTokenBalance)
            revert InvalidCap(currentTokenBalance, newCap);
        ShareMath.assertUint104(newCap);
        Types.VaultState storage vault = vaults[token];
        emit CapSet(token, vault.cap, newCap);
        vault.cap = uint104(newCap);
    }

    /**
     * @notice Sets the new newFeeRecipient_.
     * @param newFeeRecipient is the address of the new feeRecipient_.
     */
    function setFeeRecipient(
        address newFeeRecipient
    ) external onlyOwner addressIsValid(newFeeRecipient) {
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Sets the management/performance fee status enable/disable.
     * @param _performanceFee is the performance fee status
     * @param _managementFee is the management fee status
     */
    function setFeeStatus(
        bool _performanceFee,
        bool _managementFee
    ) public onlyOwner {
        isPerformanceFeeEnabled = _performanceFee;
        isManagementFeeEnable = _managementFee;
    }

    /**
     * @notice Sets the management fee for the rounds.
     * @param newManagementFee is the management fee (18 decimals). ex: 2 * 10 ** 18 = 2%
     */
    function setManagementFee(
        uint256 newManagementFee
    ) public onlyOwner numberIsNotZero(newManagementFee) {
        if (newManagementFee > 100 * FEE_MULTIPLIER) revert InvalidFee();
        // We are dividing annualized management fee by num weeks in a year
        uint256 tmpManagementFee = newManagementFee.mul(FEE_MULTIPLIER).div(
            WEEKS_PER_YEAR
        );
        emit ManagementFeeSet(managementFee, newManagementFee);
        managementFee = tmpManagementFee;
    }

    /**
     * @notice Sets the performance fee for the vault
     * @param newPerformanceFee is the performance fee (18 decimals). ex: 20 * 10 ** 18 = 20%
     */
    function setPerformanceFee(
        uint256 newPerformanceFee
    ) public numberIsNotZero(newPerformanceFee) onlyOwner {
        if (newPerformanceFee > 100 * FEE_MULTIPLIER) revert InvalidFee();
        emit PerformanceFeeSet(performanceFee, newPerformanceFee);
        performanceFee = newPerformanceFee;
    }

    /**
     * @notice Enable or Disable the asset status, so cruize can stop/resume token operations
     * @param token asset address
     * @param status enable/disable status of asset
     */
    function changeAssetStatus(
        address token,
        bool status
    ) public onlyOwner tokenIsAllowed(token) {
        isDisable[token] = status;
        emit ChangeAssetStatus(token, status);
    }

    /**
     * @param token - asset to delist from the contract.
     */
    function deListTokens(
        address token
    ) external onlyOwner tokenIsAllowed(token) {
        if (totalBalance(token,0) > 0)
            revert TokenBalanceShouldBeZero(totalBalance(token,0));
        cruizeTokens[token] = address(0);
        emit deListToken(token);
    }
}

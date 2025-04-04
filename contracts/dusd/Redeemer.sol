// SPDX-License-Identifier: MIT
/* ———————————————————————————————————————————————————————————————————————————————— *
 *    _____     ______   ______     __     __   __     __     ______   __  __       *
 *   /\  __-.  /\__  _\ /\  == \   /\ \   /\ "-.\ \   /\ \   /\__  _\ /\ \_\ \      *
 *   \ \ \/\ \ \/_/\ \/ \ \  __<   \ \ \  \ \ \-.  \  \ \ \  \/_/\ \/ \ \____ \     *
 *    \ \____-    \ \_\  \ \_\ \_\  \ \_\  \ \_\\"\_\  \ \_\    \ \_\  \/\_____\    *
 *     \/____/     \/_/   \/_/ /_/   \/_/   \/_/ \/_/   \/_/     \/_/   \/_____/    *
 *                                                                                  *
 * ————————————————————————————————— dtrinity.org ————————————————————————————————— *
 *                                                                                  *
 *                                         ▲                                        *
 *                                        ▲ ▲                                       *
 *                                                                                  *
 * ———————————————————————————————————————————————————————————————————————————————— *
 * dTRINITY Protocol: https://github.com/dtrinity                                   *
 * ———————————————————————————————————————————————————————————————————————————————— */

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-5/access/AccessControl.sol";

import "contracts/shared/Constants.sol";
import "contracts/token/IERC20Stablecoin.sol";
import "contracts/dusd/CollateralVault.sol";
import "contracts/dusd/OracleAware.sol";

contract Redeemer is AccessControl, OracleAware {
    /* Core state */

    IERC20Stablecoin public dusd;
    uint8 public immutable dusdDecimals;
    CollateralVault public collateralVault;

    uint256 public immutable USD_UNIT;

    /* Roles */

    bytes32 public constant REDEMPTION_MANAGER_ROLE =
        keccak256("REDEMPTION_MANAGER_ROLE");

    /* Errors */
    error DUSDTransferFailed();
    error SlippageTooHigh(uint256 actualCollateral, uint256 minCollateral);

    /**
     * @notice Initializes the Redeemer contract
     * @param _collateralVault The address of the collateral vault
     * @param _dusd The address of the dUSD stablecoin
     * @param _oracle The address of the price oracle
     * @dev Sets up initial roles and configuration for redemption functionality
     */
    constructor(
        address _collateralVault,
        address _dusd,
        IPriceOracleGetter _oracle
    ) OracleAware(_oracle, Constants.ORACLE_BASE_CURRENCY_UNIT) {
        collateralVault = CollateralVault(_collateralVault);
        dusd = IERC20Stablecoin(_dusd);
        dusdDecimals = dusd.decimals();
        USD_UNIT = _oracle.BASE_CURRENCY_UNIT();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(REDEMPTION_MANAGER_ROLE, msg.sender);
    }

    /* Redeemer */

    /**
     * @notice Redeems dUSD tokens for collateral from the caller
     * @param dusdAmount The amount of dUSD to redeem
     * @param collateralAsset The address of the collateral asset
     * @param minCollateral The minimum amount of collateral to receive, used for slippage protection
     */
    function redeem(
        uint256 dusdAmount,
        address collateralAsset,
        uint256 minCollateral
    ) external onlyRole(REDEMPTION_MANAGER_ROLE) {
        // Transfer dUSD from withdrawer to this contract
        if (!dusd.transferFrom(msg.sender, address(this), dusdAmount)) {
            revert DUSDTransferFailed();
        }

        // Burn the dUSD
        dusd.burn(dusdAmount);

        // Calculate collateral amount
        uint256 dusdValue = dusdAmountToUsdValue(dusdAmount);
        uint256 collateralAmount = collateralVault.assetAmountFromValue(
            dusdValue,
            collateralAsset
        );
        if (collateralAmount < minCollateral) {
            revert SlippageTooHigh(collateralAmount, minCollateral);
        }

        // Withdraw collateral from the vault
        collateralVault.withdrawTo(
            msg.sender,
            collateralAmount,
            collateralAsset
        );
    }

    /**
     * @notice Converts an amount of dUSD tokens to its equivalent USD value
     * @param dusdAmount The amount of dUSD tokens to convert
     * @return The equivalent USD value
     */
    function dusdAmountToUsdValue(
        uint256 dusdAmount
    ) public view returns (uint256) {
        return (dusdAmount * USD_UNIT) / (10 ** dusdDecimals);
    }

    /* Admin */

    /**
     * @notice Sets the collateral vault address
     * @param _collateralVault The address of the new collateral vault
     */
    function setCollateralVault(
        address _collateralVault
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        collateralVault = CollateralVault(_collateralVault);
    }
}

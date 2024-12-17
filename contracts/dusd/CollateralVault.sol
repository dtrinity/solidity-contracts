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
import "@openzeppelin/contracts-5/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-5/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-5/utils/structs/EnumerableSet.sol";

import "contracts/shared/Constants.sol";
import "contracts/lending/core/interfaces/IPriceOracleGetter.sol";
import "contracts/dusd/OracleAware.sol";

/**
 * @title CollateralVault
 * @notice Abstract contract for any contract that manages collateral assets
\ */
abstract contract CollateralVault is AccessControl, OracleAware {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* Core state */

    EnumerableSet.AddressSet internal _supportedCollaterals;

    /* Events */

    event CollateralAllowed(address indexed collateralAsset);
    event CollateralDisallowed(address indexed collateralAsset);

    /* Roles */

    bytes32 public constant COLLATERAL_MANAGER_ROLE =
        keccak256("COLLATERAL_MANAGER_ROLE");
    bytes32 public constant COLLATERAL_STRATEGY_ROLE =
        keccak256("COLLATERAL_STRATEGY_ROLE");
    bytes32 public constant COLLATERAL_WITHDRAWER_ROLE =
        keccak256("COLLATERAL_WITHDRAWER_ROLE");

    /* Errors */
    error UnsupportedCollateral(address collateralAsset);
    error CollateralAlreadyAllowed(address collateralAsset);
    error NoOracleSupport(address collateralAsset);
    error FailedToAddCollateral(address collateralAsset);
    error CollateralNotSupported(address collateralAsset);
    error MustSupportAtLeastOneCollateral();
    error FailedToRemoveCollateral(address collateralAsset);

    /**
     * @notice Initializes the vault with an oracle and sets up initial roles
     * @dev Grants all roles to the contract deployer initially
     * @param oracle The price oracle to use for collateral valuation
     */
    constructor(
        IPriceOracleGetter oracle
    ) OracleAware(oracle, Constants.ORACLE_BASE_CURRENCY_UNIT) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // This is the super admin
        grantRole(COLLATERAL_MANAGER_ROLE, msg.sender);
        grantRole(COLLATERAL_WITHDRAWER_ROLE, msg.sender);
        grantRole(COLLATERAL_STRATEGY_ROLE, msg.sender);
    }

    /* Deposit */

    /**
     * @notice Deposit collateral into the vault
     * @param collateralAmount The amount of collateral to deposit
     * @param collateralAsset The address of the collateral asset
     */
    function deposit(uint256 collateralAmount, address collateralAsset) public {
        return _deposit(msg.sender, collateralAmount, collateralAsset);
    }

    /**
     * @notice Deposit collateral into the vault from a specific address
     * @param depositer The address providing the collateral
     * @param collateralAmount The amount of collateral to deposit
     * @param collateralAsset The address of the collateral asset
     */
    function depositFrom(
        address depositer,
        uint256 collateralAmount,
        address collateralAsset
    ) public {
        return _deposit(depositer, collateralAmount, collateralAsset);
    }

    /**
     * @notice Internal function to deposit collateral into the vault
     * @param depositer The address providing the collateral
     * @param collateralAmount The amount of collateral to deposit
     * @param collateralAsset The address of the collateral asset
     */
    function _deposit(
        address depositer,
        uint256 collateralAmount,
        address collateralAsset
    ) internal {
        if (!_supportedCollaterals.contains(collateralAsset)) {
            revert UnsupportedCollateral(collateralAsset);
        }

        IERC20Metadata(collateralAsset).safeTransferFrom(
            depositer,
            address(this),
            collateralAmount
        );
    }

    /* Withdrawal */

    /**
     * @notice Withdraws collateral from the vault
     * @param collateralAmount The amount of collateral to withdraw
     * @param collateralAsset The address of the collateral asset
     */
    function withdraw(
        uint256 collateralAmount,
        address collateralAsset
    ) public onlyRole(COLLATERAL_WITHDRAWER_ROLE) {
        return _withdraw(msg.sender, collateralAmount, collateralAsset);
    }

    /**
     * @notice Withdraws collateral from the vault to a specific address
     * @param recipient The address receiving the collateral
     * @param collateralAmount The amount of collateral to withdraw
     * @param collateralAsset The address of the collateral asset
     */
    function withdrawTo(
        address recipient,
        uint256 collateralAmount,
        address collateralAsset
    ) public onlyRole(COLLATERAL_WITHDRAWER_ROLE) {
        return _withdraw(recipient, collateralAmount, collateralAsset);
    }

    /**
     * @notice Internal function to withdraw collateral from the vault
     * @param withdrawer The address withdrawing the collateral
     * @param collateralAmount The amount of collateral to withdraw
     * @param collateralAsset The address of the collateral asset
     */
    function _withdraw(
        address withdrawer,
        uint256 collateralAmount,
        address collateralAsset
    ) internal {
        IERC20Metadata(collateralAsset).safeTransfer(
            withdrawer,
            collateralAmount
        );
    }

    /* Collateral Info */

    /**
     * @notice Calculates the total value of all assets in the vault
     * @return usdValue The total value of all assets in USD
     */
    function totalValue() public view virtual returns (uint256 usdValue);

    /**
     * @notice Calculates the USD value of a given amount of an asset
     * @param assetAmount The amount of the asset
     * @param asset The address of the asset
     * @return usdValue The USD value of the asset
     */
    function assetValueFromAmount(
        uint256 assetAmount,
        address asset
    ) public view returns (uint256 usdValue) {
        uint256 assetPrice = oracle.getAssetPrice(asset);
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return (assetPrice * assetAmount) / (10 ** assetDecimals);
    }

    /**
     * @notice Calculates the amount of an asset that corresponds to a given USD value
     * @param usdValue The USD value
     * @param asset The address of the asset
     * @return assetAmount The amount of the asset
     */
    function assetAmountFromValue(
        uint256 usdValue,
        address asset
    ) public view returns (uint256 assetAmount) {
        uint256 assetPrice = oracle.getAssetPrice(asset);
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return (usdValue * (10 ** assetDecimals)) / assetPrice;
    }

    /* Collateral management */

    /**
     * @notice Allows a new collateral asset
     * @param collateralAsset The address of the collateral asset
     */
    function allowCollateral(
        address collateralAsset
    ) public onlyRole(COLLATERAL_MANAGER_ROLE) {
        if (_supportedCollaterals.contains(collateralAsset)) {
            revert CollateralAlreadyAllowed(collateralAsset);
        }
        if (oracle.getAssetPrice(collateralAsset) == 0) {
            revert NoOracleSupport(collateralAsset);
        }
        if (!_supportedCollaterals.add(collateralAsset)) {
            revert FailedToAddCollateral(collateralAsset);
        }
        emit CollateralAllowed(collateralAsset);
    }

    /**
     * @notice Disallows a previously supported collateral asset
     * @dev Requires at least one collateral asset to remain supported
     * @param collateralAsset The address of the collateral asset to disallow
     */
    function disallowCollateral(
        address collateralAsset
    ) public onlyRole(COLLATERAL_MANAGER_ROLE) {
        if (!_supportedCollaterals.contains(collateralAsset)) {
            revert CollateralNotSupported(collateralAsset);
        }
        if (_supportedCollaterals.length() <= 1) {
            revert MustSupportAtLeastOneCollateral();
        }
        if (!_supportedCollaterals.remove(collateralAsset)) {
            revert FailedToRemoveCollateral(collateralAsset);
        }

        emit CollateralDisallowed(collateralAsset);
    }

    /**
     * @notice Checks if a given asset is supported as collateral
     * @param collateralAsset The address of the collateral asset to check
     * @return bool True if the asset is supported, false otherwise
     */
    function isCollateralSupported(
        address collateralAsset
    ) public view returns (bool) {
        return _supportedCollaterals.contains(collateralAsset);
    }

    /**
     * @notice Returns a list of all supported collateral assets
     * @return address[] Array of collateral asset addresses
     */
    function listCollateral() public view returns (address[] memory) {
        return _supportedCollaterals.values();
    }

    /**
     * @notice Calculates the total USD value of all supported collateral assets in the vault
     * @dev Iterates through all supported collaterals and sums their USD values
     * @return uint256 The total value in USD
     */
    function _totalValueOfSupportedCollaterals()
        internal
        view
        returns (uint256)
    {
        uint256 totalUsdValue = 0;
        for (uint256 i = 0; i < _supportedCollaterals.length(); i++) {
            address collateral = _supportedCollaterals.at(i);
            uint256 collateralPrice = oracle.getAssetPrice(collateral);
            uint8 collateralDecimals = IERC20Metadata(collateral).decimals();
            uint256 collateralValue = (collateralPrice *
                IERC20Metadata(collateral).balanceOf(address(this))) /
                (10 ** collateralDecimals);
            totalUsdValue += collateralValue;
        }
        return totalUsdValue;
    }
}
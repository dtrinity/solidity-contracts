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
import "@openzeppelin/contracts-5/utils/structs/EnumerableMap.sol";
import "contracts/shared/Constants.sol";
import "contracts/token/IERC20Stablecoin.sol";
import "contracts/dusd/AmoVault.sol";

/**
 * @title AmoManager
 * @dev Manages AMOs for dUSD
 * Handles allocation, deallocation, collateral management, and profit management for AMO vaults.
 */
contract AmoManager is AccessControl, OracleAware {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /* Core state */

    EnumerableMap.AddressToUintMap private _amoVaults;
    uint256 public totalAllocated;
    IERC20Stablecoin public dusd;
    CollateralVault public collateralHolderVault;

    uint256 public immutable USD_UNIT;

    /* Events */

    event AmoVaultSet(address indexed amoVault, bool isActive);
    event AmoAllocated(address indexed amoVault, uint256 dusdAmount);
    event AmoDeallocated(address indexed amoVault, uint256 dusdAmount);
    event ProfitsWithdrawn(address indexed amoVault, uint256 amount);

    /* Roles */

    bytes32 public constant AMO_ALLOCATOR_ROLE =
        keccak256("AMO_ALLOCATOR_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE =
        keccak256("FEE_COLLECTOR_ROLE");

    /* Errors */

    error InactiveAmoVault(address amoVault);
    error AmoSupplyInvariantViolation(
        uint256 startingSupply,
        uint256 endingSupply
    );
    error AmoVaultAlreadyEnabled(address amoVault);
    error CannotTransferDUSD();
    error InsufficientProfits(
        uint256 takeProfitValueInUsd,
        int256 availableProfitInUsd
    );

    /**
     * @notice Initializes the AmoManager contract.
     * @param _dusd The address of the dUSD stablecoin.
     * @param _collateralHolderVault The address of the collateral holder vault.
     * @param _oracle The oracle for price feeds.
     */
    constructor(
        address _dusd,
        address _collateralHolderVault,
        IPriceOracleGetter _oracle
    ) OracleAware(_oracle, Constants.ORACLE_BASE_CURRENCY_UNIT) {
        dusd = IERC20Stablecoin(_dusd);
        collateralHolderVault = CollateralVault(_collateralHolderVault);

        USD_UNIT = oracle.BASE_CURRENCY_UNIT();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(AMO_ALLOCATOR_ROLE, msg.sender);
        grantRole(FEE_COLLECTOR_ROLE, msg.sender);
    }

    /* AMO */

    /**
     * @notice Allocates AMO tokens to an AMO vault.
     * @param amoVault The address of the AMO vault.
     * @param dusdAmount The amount of dUSD to allocate.
     */
    function allocateAmo(
        address amoVault,
        uint256 dusdAmount
    ) public onlyRole(AMO_ALLOCATOR_ROLE) {
        uint256 startingAmoSupply = totalAmoSupply();

        // Make sure the vault is active
        if (!isAmoActive(amoVault)) {
            revert InactiveAmoVault(amoVault);
        }

        // Update the allocation for this vault
        (, uint256 currentAllocation) = _amoVaults.tryGet(amoVault);
        _amoVaults.set(amoVault, currentAllocation + dusdAmount);

        // Make the deposit
        totalAllocated += dusdAmount;
        dusd.transfer(amoVault, dusdAmount);

        // Check invariants
        uint256 endingAmoSupply = totalAmoSupply();
        if (endingAmoSupply != startingAmoSupply) {
            revert AmoSupplyInvariantViolation(
                startingAmoSupply,
                endingAmoSupply
            );
        }

        emit AmoAllocated(amoVault, dusdAmount);
    }

    /**
     * @notice Deallocates AMO tokens from an AMO vault.
     * @param amoVault The address of the AMO vault.
     * @param dusdAmount The amount of dUSD to deallocate.
     */
    function deallocateAmo(
        address amoVault,
        uint256 dusdAmount
    ) public onlyRole(AMO_ALLOCATOR_ROLE) {
        uint256 startingAmoSupply = totalAmoSupply();

        // We don't require that the vault is active or has allocation, since we want to allow withdrawing from inactive vaults

        // If the vault is still active, make sure it has enough allocation and decrease it
        (, uint256 currentAllocation) = _amoVaults.tryGet(amoVault);
        if (currentAllocation > 0) {
            // Update the allocation for this vault
            _amoVaults.set(amoVault, currentAllocation - dusdAmount);
        }

        // Make the withdrawal
        totalAllocated -= dusdAmount;
        dusd.transferFrom(amoVault, address(this), dusdAmount);

        // Check invariants
        uint256 endingAmoSupply = totalAmoSupply();
        if (endingAmoSupply != startingAmoSupply) {
            revert AmoSupplyInvariantViolation(
                startingAmoSupply,
                endingAmoSupply
            );
        }

        emit AmoDeallocated(amoVault, dusdAmount);
    }

    /**
     * @notice Returns the total AMO supply.
     * @return The total AMO supply.
     */
    function totalAmoSupply() public view returns (uint256) {
        uint256 freeBalance = dusd.balanceOf(address(this));
        return freeBalance + totalAllocated;
    }

    /**
     * @notice Decreases the AMO supply by burning dUSD.
     * @param dusdAmount The amount of dUSD to burn.
     */
    function decreaseAmoSupply(
        uint256 dusdAmount
    ) public onlyRole(AMO_ALLOCATOR_ROLE) {
        dusd.burn(dusdAmount);
    }

    /**
     * @notice Checks if an AMO vault is active.
     * @param amoVault The address of the AMO vault to check.
     * @return True if the AMO vault is active, false otherwise.
     */
    function isAmoActive(address amoVault) public view returns (bool) {
        return _amoVaults.contains(amoVault);
    }

    /**
     * @notice Returns the allocation for a specific AMO vault.
     * @param amoVault The address of the AMO vault.
     * @return The current allocation for the vault.
     */
    function amoVaultAllocation(
        address amoVault
    ) public view returns (uint256) {
        (bool exists, uint256 allocation) = _amoVaults.tryGet(amoVault);
        return exists ? allocation : 0;
    }

    /**
     * @notice Returns the list of all AMO vaults.
     * @return The list of AMO vault addresses.
     */
    function amoVaults() public view returns (address[] memory) {
        return _amoVaults.keys();
    }

    /**
     * @notice Enables an AMO vault.
     * @param amoVault The address of the AMO vault.
     */
    function enableAmoVault(
        address amoVault
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_amoVaults.contains(amoVault)) {
            revert AmoVaultAlreadyEnabled(amoVault);
        }
        _amoVaults.set(amoVault, 0);
        emit AmoVaultSet(amoVault, true);
    }

    /**
     * @notice Disables an AMO vault.
     * @param amoVault The address of the AMO vault.
     */
    function disableAmoVault(
        address amoVault
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_amoVaults.contains(amoVault)) {
            revert InactiveAmoVault(amoVault);
        }
        _amoVaults.remove(amoVault);
        emit AmoVaultSet(amoVault, false);
    }

    /* Collateral Management */

    /**
     * @notice Returns the total collateral value of all active AMO vaults.
     * @return The total collateral value in USD.
     */
    function totalCollateralValue() public view returns (uint256) {
        uint256 totalUsdValue = 0;
        for (uint256 i = 0; i < _amoVaults.length(); i++) {
            (address vaultAddress, ) = _amoVaults.at(i);
            if (isAmoActive(vaultAddress)) {
                totalUsdValue += AmoVault(vaultAddress).totalCollateralValue();
            }
        }
        return totalUsdValue;
    }

    /**
     * @notice Transfers collateral from an AMO vault to the holding vault.
     * @param amoVault The address of the AMO vault.
     * @param token The address of the collateral token to transfer.
     * @param amount The amount of collateral to transfer.
     */
    function transferFromAmoVaultToHoldingVault(
        address amoVault,
        address token,
        uint256 amount
    ) public onlyRole(AMO_ALLOCATOR_ROLE) {
        if (token == address(dusd)) {
            revert CannotTransferDUSD();
        }

        // Update allocation
        // A note on why we modify AMO allocation when we withdraw collateral:
        // 1. When dUSD AMO enters the AMO vault, the dUSD is initially unbacked
        // 2. Over time the AMO vault accrues collateral in exchange for distributing dUSD
        // 3. We may be able to make better use of that collateral in a different collateral vault
        // 4. So we transfer the collateral out of the AMO vault, but at that point the dUSD that
        //    converted to that collateral is now free-floating and fully backed
        // 5. Thus we decrement the AMO allocation to reflect the fact that the dUSD is no longer
        //    unbacked, but is actually fully backed and circulating
        uint256 collateralUsdValue = collateralHolderVault.assetValueFromAmount(
            amount,
            token
        );
        uint256 collateralInDusd = usdValueToDusdAmount(collateralUsdValue);
        (, uint256 currentAllocation) = _amoVaults.tryGet(amoVault);
        _amoVaults.set(amoVault, currentAllocation - collateralInDusd);
        totalAllocated -= collateralInDusd;

        // Transfer the collateral
        AmoVault(amoVault).withdrawTo(
            address(collateralHolderVault),
            amount,
            token
        );
    }

    /**
     * @notice Transfers collateral from the holding vault to an AMO vault.
     * @param amoVault The address of the AMO vault.
     * @param token The address of the collateral token to transfer.
     * @param amount The amount of collateral to transfer.
     */
    function transferFromHoldingVaultToAmoVault(
        address amoVault,
        address token,
        uint256 amount
    ) public onlyRole(AMO_ALLOCATOR_ROLE) {
        if (token == address(dusd)) {
            revert CannotTransferDUSD();
        }
        if (!_amoVaults.contains(amoVault)) {
            revert InactiveAmoVault(amoVault);
        }

        // Update allocation
        // A note on why we modify AMO allocation when we deposit collateral:
        // 1. When we deposit collateral, it can be used to buy back dUSD
        // 2. When we buy back dUSD, the dUSD is now unbacked (a redemption)
        // 3. Thus any collateral deposited to an AMO vault can create unbacked dUSD,
        //    which means the AMO allocation for that vault must be increased to reflect this
        uint256 collateralUsdValue = collateralHolderVault.assetValueFromAmount(
            amount,
            token
        );
        uint256 collateralInDusd = usdValueToDusdAmount(collateralUsdValue);
        (, uint256 currentAllocation) = _amoVaults.tryGet(amoVault);
        _amoVaults.set(amoVault, currentAllocation + collateralInDusd);
        totalAllocated += collateralInDusd;

        // Transfer the collateral
        collateralHolderVault.withdrawTo(amoVault, amount, token);
    }

    /* Profit Management */

    /**
     * @notice Returns the available profit for a specific vault in USD.
     * @param vaultAddress The address of the AMO vault to check.
     * @return The available profit in USD (can be negative).
     */
    function availableVaultProfitsInUsd(
        address vaultAddress
    ) public view returns (int256) {
        uint256 totalVaultValueInUsd = AmoVault(vaultAddress).totalValue();
        uint256 allocatedDusd = amoVaultAllocation(vaultAddress);
        uint256 allocatedValueInUsd = dusdAmountToUsdValue(allocatedDusd);

        return int256(totalVaultValueInUsd) - int256(allocatedValueInUsd);
    }

    /**
     * @notice Withdraws profits from an AMO vault to a recipient.
     * @param amoVault The AMO vault from which to withdraw profits.
     * @param recipient The address to receive the profits.
     * @param takeProfitToken The collateral token to withdraw.
     * @param takeProfitAmount The amount of collateral to withdraw.
     * @return takeProfitValueInUsd The value of the withdrawn profits in USD.
     */
    function withdrawProfits(
        AmoVault amoVault,
        address recipient,
        address takeProfitToken,
        uint256 takeProfitAmount
    )
        public
        onlyRole(FEE_COLLECTOR_ROLE)
        returns (uint256 takeProfitValueInUsd)
    {
        // Leave open the possibility of withdrawing profits from inactive vaults

        takeProfitValueInUsd = amoVault.assetValueFromAmount(
            takeProfitAmount,
            takeProfitToken
        );

        int256 _availableProfitInUsd = availableVaultProfitsInUsd(
            address(amoVault)
        );

        // Make sure we are withdrawing less than the available profit
        if (
            _availableProfitInUsd <= 0 ||
            int256(takeProfitValueInUsd) > _availableProfitInUsd
        ) {
            revert InsufficientProfits(
                takeProfitValueInUsd,
                _availableProfitInUsd
            );
        }

        // Withdraw profits from the vault
        amoVault.withdrawTo(recipient, takeProfitAmount, takeProfitToken);

        emit ProfitsWithdrawn(address(amoVault), takeProfitValueInUsd);

        return takeProfitValueInUsd;
    }

    /**
     * @notice Returns the total available profit across all AMO vaults in USD.
     * @return The total available profit in USD.
     */
    function availableProfitInUsd() public view returns (int256) {
        int256 totalProfit = 0;

        // Iterate through all AMO vaults
        for (uint256 i = 0; i < _amoVaults.length(); i++) {
            (address vaultAddress, ) = _amoVaults.at(i);

            if (isAmoActive(vaultAddress)) {
                totalProfit += availableVaultProfitsInUsd(vaultAddress);
            }
        }

        return totalProfit;
    }

    /* Utility */

    /**
     * @notice Converts a USD value to an equivalent amount of dUSD tokens.
     * @param usdValue The amount of USD value to convert.
     * @return The equivalent amount of dUSD tokens.
     */
    function usdValueToDusdAmount(
        uint256 usdValue
    ) public view returns (uint256) {
        uint8 dusdDecimals = dusd.decimals();
        return (usdValue * (10 ** dusdDecimals)) / USD_UNIT;
    }

    /**
     * @notice Converts an amount of dUSD tokens to an equivalent USD value.
     * @param dusdAmount The amount of dUSD tokens to convert.
     * @return The equivalent amount of USD value.
     */
    function dusdAmountToUsdValue(
        uint256 dusdAmount
    ) public view returns (uint256) {
        uint8 dusdDecimals = dusd.decimals();
        return
            (dusdAmount * oracle.getAssetPrice(address(dusd))) /
            (10 ** dusdDecimals);
    }

    /* Admin */

    /**
     * @notice Sets the collateral vault address
     * @param _collateralVault The address of the new collateral vault
     */
    function setCollateralVault(
        address _collateralVault
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        collateralHolderVault = CollateralVault(_collateralVault);
    }
}

/**
 * @title ICollateralSum
 * @dev Interface for contracts that can provide total collateral value.
 */
interface ICollateralSum {
    /**
     * @notice Returns the total collateral value of the implementing contract.
     * @return The total collateral value in base value (e.g., USD).
     */
    function totalCollateralValue() external view returns (uint256);
}

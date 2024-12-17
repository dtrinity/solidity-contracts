// SPDX-License-Identifier: AGPL-3.0
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

pragma solidity ^0.8.10;

import {IERC20Detailed} from "contracts/lending/core/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IERC20WithPermit} from "contracts/lending/core/interfaces/IERC20WithPermit.sol";
import {IPoolAddressesProvider} from "contracts/lending/core/interfaces/IPoolAddressesProvider.sol";
import {SafeERC20} from "contracts/lending/core/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {SafeMath} from "contracts/lending/core/dependencies/openzeppelin/contracts/SafeMath.sol";
import {BaseDSwapSellAdapter} from "./BaseDSwapSellAdapter.sol";
import {ReentrancyGuard} from "../../dependencies/openzeppelin/ReentrancyGuard.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";

/**
 * @title DSwapLiquiditySwapAdapter
 * @notice Adapter to swap liquidity using dSwap
 */
contract DSwapLiquiditySwapAdapter is BaseDSwapSellAdapter, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Detailed;

    constructor(
        IPoolAddressesProvider addressesProvider,
        ISwapRouter swapRouter,
        address owner
    ) BaseDSwapSellAdapter(addressesProvider, swapRouter) {
        transferOwnership(owner);
    }

    /**
     * @dev Swaps the received reserve amount from the flash loan into the asset specified in the params.
     * The received funds from the swap are then deposited into the protocol on behalf of the user.
     * The user should give this contract allowance to pull the ATokens in order to withdraw the underlying asset and repay the flash loan.
     * @param asset The address of the flash-borrowed asset
     * @param amount The amount of the flash-borrowed asset
     * @param premium The fee of the flash-borrowed asset
     * @param initiator The address of the flashloan initiator
     * @param params The byte-encoded params passed when initiating the flashloan
     * @return True if the execution of the operation succeeds, false otherwise
     *   address assetToSwapTo Address of the underlying asset to be swapped to and deposited
     *   uint256 minAmountToReceive Min amount to be received from the swap
     *   uint256 swapAllBalanceOffset Set to offset of fromAmount in Augustus calldata if wanting to swap all balance, otherwise 0
     *   bytes memory path Multi-hop path of the swap
     *   PermitSignature permitParams Struct containing the permit signatures, set to all zeroes if not used
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override nonReentrant returns (bool) {
        require(msg.sender == address(POOL), "CALLER_MUST_BE_POOL");

        uint256 flashLoanAmount = amount;
        uint256 premiumLocal = premium;
        address initiatorLocal = initiator;
        IERC20Detailed assetToSwapFrom = IERC20Detailed(asset);
        (
            IERC20Detailed assetToSwapTo,
            uint256 minAmountToReceive,
            uint256 swapAllBalanceOffset,
            bytes memory path,
            PermitSignature memory permitParams
        ) = abi.decode(
                params,
                (IERC20Detailed, uint256, uint256, bytes, PermitSignature)
            );

        _swapLiquidity(
            swapAllBalanceOffset,
            path,
            permitParams,
            flashLoanAmount,
            premiumLocal,
            initiatorLocal,
            assetToSwapFrom,
            assetToSwapTo,
            minAmountToReceive
        );

        return true;
    }

    /**
     * @dev Swaps an amount of an asset to another and deposits the new asset amount on behalf of the user without using a flash loan.
     * This method can be used when the temporary transfer of the collateral asset to this contract does not affect the user position.
     * The user should give this contract allowance to pull the ATokens in order to withdraw the underlying asset and perform the swap.
     * @param assetToSwapFrom Address of the underlying asset to be swapped from
     * @param assetToSwapTo Address of the underlying asset to be swapped to and deposited
     * @param amountToSwap Amount to be swapped, or maximum amount when swapping all balance
     * @param minAmountToReceive Minimum amount to be received from the swap
     * @param swapAllBalanceOffset Set to offset of fromAmount in Augustus calldata if wanting to swap all balance, otherwise 0
     * @param path Multi-hop path of the swap
     * @param permitParams Struct containing the permit signatures, set to all zeroes if not used
     */
    function swapAndDeposit(
        IERC20Detailed assetToSwapFrom,
        IERC20Detailed assetToSwapTo,
        uint256 amountToSwap,
        uint256 minAmountToReceive,
        uint256 swapAllBalanceOffset,
        bytes memory path,
        PermitSignature calldata permitParams
    ) external nonReentrant {
        IERC20WithPermit aToken = IERC20WithPermit(
            _getReserveData(address(assetToSwapFrom)).aTokenAddress
        );

        if (swapAllBalanceOffset != 0) {
            uint256 balance = aToken.balanceOf(msg.sender);
            require(balance <= amountToSwap, "INSUFFICIENT_AMOUNT_TO_SWAP");
            amountToSwap = balance;
        }

        _pullATokenAndWithdraw(
            address(assetToSwapFrom),
            aToken,
            msg.sender,
            amountToSwap,
            permitParams
        );

        uint256 amountReceived = _sellOnDSwap(
            assetToSwapFrom,
            assetToSwapTo,
            amountToSwap,
            minAmountToReceive,
            path
        );

        assetToSwapTo.safeApprove(address(POOL), 0);
        assetToSwapTo.safeApprove(address(POOL), amountReceived);
        POOL.deposit(address(assetToSwapTo), amountReceived, msg.sender, 0);
    }

    /**
     * @dev Swaps an amount of an asset to another and deposits the funds on behalf of the initiator.
     * @param swapAllBalanceOffset Set to offset of fromAmount in Augustus calldata if wanting to swap all balance, otherwise 0
     * @param path Multi-hop path of the swap
     * @param permitParams Struct containing the permit signatures, set to all zeroes if not used
     * @param flashLoanAmount Amount of the flash loan i.e. maximum amount to swap
     * @param premium Fee of the flash loan
     * @param initiator Account that initiated the flash loan
     * @param assetToSwapFrom Address of the underyling asset to be swapped from
     * @param assetToSwapTo Address of the underlying asset to be swapped to and deposited
     * @param minAmountToReceive Min amount to be received from the swap
     */
    function _swapLiquidity(
        uint256 swapAllBalanceOffset,
        bytes memory path,
        PermitSignature memory permitParams,
        uint256 flashLoanAmount,
        uint256 premium,
        address initiator,
        IERC20Detailed assetToSwapFrom,
        IERC20Detailed assetToSwapTo,
        uint256 minAmountToReceive
    ) internal {
        IERC20WithPermit aToken = IERC20WithPermit(
            _getReserveData(address(assetToSwapFrom)).aTokenAddress
        );
        uint256 amountToSwap = flashLoanAmount;

        uint256 balance = aToken.balanceOf(initiator);
        if (swapAllBalanceOffset != 0) {
            uint256 balanceToSwap = balance.sub(premium);
            require(
                balanceToSwap <= amountToSwap,
                "INSUFFICIENT_AMOUNT_TO_SWAP"
            );
            amountToSwap = balanceToSwap;
        } else {
            require(
                balance >= amountToSwap.add(premium),
                "INSUFFICIENT_ATOKEN_BALANCE"
            );
        }

        uint256 amountReceived = _sellOnDSwap(
            assetToSwapFrom,
            assetToSwapTo,
            amountToSwap,
            minAmountToReceive,
            path
        );

        assetToSwapTo.safeApprove(address(POOL), 0);
        assetToSwapTo.safeApprove(address(POOL), amountReceived);
        POOL.deposit(address(assetToSwapTo), amountReceived, initiator, 0);

        _pullATokenAndWithdraw(
            address(assetToSwapFrom),
            aToken,
            initiator,
            amountToSwap.add(premium),
            permitParams
        );

        // Repay flash loan
        assetToSwapFrom.safeApprove(address(POOL), 0);
        assetToSwapFrom.safeApprove(
            address(POOL),
            flashLoanAmount.add(premium)
        );
    }
}

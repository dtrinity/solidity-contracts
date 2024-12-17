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

pragma solidity 0.8.20;

import "contracts/lending/core/interfaces/IPriceOracleGetter.sol";
import "../interface/IOracleWrapper.sol";

contract HardPegOracleWrapper is IOracleWrapper {
    uint256 public immutable pricePeg;
    address public constant BASE_CURRENCY = address(0); // Commonly used for USD

    uint256 public BASE_CURRENCY_UNIT;

    constructor(uint256 _pricePeg, uint256 _baseCurrencyUnit) {
        pricePeg = _pricePeg;
        BASE_CURRENCY_UNIT = _baseCurrencyUnit;
    }

    /**
     * @dev Get the price info of an asset
     */
    function getPriceInfo(
        address // asset
    ) external view returns (uint256 price, bool isAlive) {
        return (pricePeg, true);
    }

    /**
     * @dev Get the price of an asset
     */
    function getAssetPrice(
        address // asset
    ) external view override returns (uint256) {
        return pricePeg;
    }
}

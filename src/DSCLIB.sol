// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./ORACLE-LIB.sol";

/**
 * @title engineLibrary
 * @notice Provides core calculation logic for collateral valuation and health factor status determination in a DeFi lending protocol.
 * @dev This library contains only internal functions, designed to be used exclusively by a primary contract (e.g., a `DecentralizedStablecoinEngine`).
 * It relies on `OracleLib` for safe, non-stale price feed retrieval.
 *
 * Usage:
 * A consuming contract simply needs to import this library and can call its internal functions directly:
 *
 * ```solidity
 * import {engineLibrary} from "./engineLibrary.sol";
 * contract DSC_Engine {
 * // All engineLibrary functions are directly available by name (e.g., engineLibrary._getCollateralValue(...))
 * }
 * ```
 */
library engineLibrary {
    using OracleLib for AggregatorV3Interface;

    string private constant GOOD = "Good!!!";
    string private constant WARNING = "Warning!!!";
    string private constant RISK = "Risk!!!";
    uint128 private constant s_MAX_THRESHOLD = 1500000000000000000; // 1.5e18 (150%) - Health factor above this is considered 'Good'.
    uint128 private constant s_MIN_THRESHOLD = 1200000000000000000; // 1.2e18 (120%) - Health factor below this is considered 'Risk'.
    uint128 private constant s_PRECISION = 1e18;
    // Chainlink price feeds usually return 8 decimals. We multiply by 1e10 to scale to 1e18 for consistent calculations.
    uint128 private constant s_PRICE_FEED_SCALE = 1e10;

    /**
     * @notice Calculates the total USD value of a given amount of collateral tokens.
     * @param _priceFeedAddress Chainlink price feed address for the collateral asset.
     * @param _amount Amount of collateral tokens (assumed to be 1e18 precision).
     * @return totalValue The total USD value of the amount, scaled to 1e18.
     * @return assetPrice The current price of the collateral asset in USD, scaled to 1e18.
     * @dev Fetches a fresh price using `OracleLib.roundDataStaleCheck()` to ensure the price is not stale.
     * Price feeds are assumed to return 8 decimals and are scaled up by 1e10 internally.
     */
    function _getCollateralValue(address _priceFeedAddress, uint256 _amount)
        internal
        view
        returns (uint256 totalValue, uint256 assetPrice)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);
        // Uses OracleLib's roundDataStaleCheck to ensure a fresh, non-stale price
        (, int256 answer,,,) = priceFeed.roundDataStaleCheck();

        // 1. Calculate Asset Price scaled to 1e18
        // answer (8 decimals) * 1e10 = assetPrice (1e18)
        assetPrice = uint256(answer) * s_PRICE_FEED_SCALE;

        // 2. Calculate Total Value
        // Value = (assetPrice (1e18) * Amount (1e18)) / 1e18
        totalValue = (assetPrice * _amount) / s_PRECISION;
        return (totalValue, assetPrice);
    }

    /**
     * @notice Determines the human-readable and encoded health status based on the health factor.
     * @param _userInfo The health factor (Collateral Value / Borrowed Value), scaled to 1e18.
     * @return encoded Encoded status using keccak256 for gas-efficient comparison in the consuming contract.
     * @return status Human-readable status: "Good!!!" (>= 150%), "Warning!!!" (120% to 150%), or "Risk!!!" (< 120%).
     * @dev Statuses are defined by `s_MAX_THRESHOLD` (150%) and `s_MIN_THRESHOLD` (120%).
     */
    function _getHealthStatus(uint256 _userInfo) internal pure returns (bytes32 encoded, string memory status) {
        if (_userInfo >= s_MAX_THRESHOLD) {
            bytes32 encodedGood = _statusString(GOOD);
            return (encodedGood, GOOD);
        } else if (_userInfo < s_MAX_THRESHOLD && _userInfo >= s_MIN_THRESHOLD) {
            bytes32 encodedWarning = _statusString(WARNING);
            return (encodedWarning, WARNING);
        } else {
            // _userInfo < s_MIN_THRESHOLD
            bytes32 encodedRisk = _statusString(RISK);
            return (encodedRisk, RISK);
        }
    }

    /**
     * @notice Encodes a status string using keccak256.
     * @param _status The string to encode (e.g., "Risk!!!").
     * @return bytes32 The encoded status hash.
     * @dev Used internally by `_getHealthStatus` to provide a bytes32 result that is cheaper to compare than a string.
     */
    function _statusString(string memory _status) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_status));
    }
}

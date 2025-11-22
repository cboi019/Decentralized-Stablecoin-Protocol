// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__PRICE_IS_STALE();
    uint256 private constant HEART_BEAT = 60 minutes;

    function roundDataStaleCheck(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            _priceFeed.latestRoundData();

        uint256 lastUpdate = block.timestamp - updatedAt;
        if (lastUpdate > HEART_BEAT) revert OracleLib__PRICE_IS_STALE();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

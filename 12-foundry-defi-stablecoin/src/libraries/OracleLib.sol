// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @dev Check the Chainlink oracle for stale data.
/// It revert if it happens to "freeze" everything.
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundID, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            _priceFeed.latestRoundData();

        uint256 timeSinceLastUpdate = block.timestamp - updatedAt;
        if (timeSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundID, answer, startedAt, updatedAt, answeredInRound);
    }
}

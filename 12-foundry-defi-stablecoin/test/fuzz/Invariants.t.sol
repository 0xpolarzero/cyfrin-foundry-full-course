// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

import {IERC20} from "../../src/interfaces/IERC20.sol";

import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSCEngine deployer;
    HelperConfig config;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    DSCEngine.Collateral[] collaterals;

    function setUp() external {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run();

        (DSCEngine.Collateral[] memory collateralArray,) = config.getActiveNetworkConfig();
        for (uint256 i = 0; i < collateralArray.length; i++) {
            collaterals.push(collateralArray[i]);
        }

        // Go wild on DSCEngine
        // targetContract(address(dscEngine));

        // But since we're using a handler instead
        Handler handler = new Handler(dscEngine, dsc, config);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() external view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < collaterals.length; i++) {
            uint256 collateralDeposited = IERC20(collaterals[i].tokenAddress).balanceOf(address(dscEngine));
            totalCollateralValueInUsd += dscEngine.getUsdValue(collaterals[i].tokenAddress, collateralDeposited);
        }

        assert(totalCollateralValueInUsd >= totalSupply);
    }

    function invariant_gettersCantRevert() public view {
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getCollateralTokens();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getPrecision();
        dscEngine.getDsc();
        // dscEngine.getTokenAmountFromUsd();
        // dscEngine.getCollateralTokenPriceFeed();
        // dscEngine.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}

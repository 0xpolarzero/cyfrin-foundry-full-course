// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {Utils} from "../../src/libraries/Utils.sol";

contract DSCEngineSymbolic is SymTest, Test {
    /* -------------------------------- CONTRACTS ------------------------------- */
    DecentralizedStableCoin private dsc;
    DSCEngine private dscEngine;

    MockERC20 collateralA;
    MockERC20 collateralB;
    MockV3Aggregator collateralAPriceFeed;
    MockV3Aggregator collateralBPriceFeed;

    /* -------------------------------- CONSTANTS ------------------------------- */
    uint8 public constant PRICE_FEED_DECIMALS = 8;

    DSCEngine.Collateral[] public collaterals;

    /* -------------------------------------------------------------------------- */
    /*                                     SETUP                                  */
    /* -------------------------------------------------------------------------- */

    function setUp() external {
        for (uint256 i = 0; i < 3; i++) {
            int256 priceCollateralUsd = svm.createInt256("priceCollateralUsd");
            uint8 decimals = uint8(svm.createUint(8, "decimals"));

            MockV3Aggregator priceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, priceCollateralUsd);
            MockERC20 collateral = new MockERC20("Collateral", "CTRL", decimals);
            collaterals.push(DSCEngine.Collateral(address(collateral), address(priceFeed), decimals));

            address receiver = svm.createAddress("receiver");
            uint256 amount = svm.createUint256("amount");

            collateral.mint(receiver, amount);
        }

        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(collaterals, address(dsc));

        dsc.transferOwnership(address(dscEngine));
    }

    /* -------------------------------------------------------------------------- */
    /*                              depositCollateral                             */
    /* -------------------------------------------------------------------------- */

    function check_depositCollateral_revertsIfCollateralZero() external {
        address caller = svm.createAddress("caller");
        uint256 amount = svm.createUint256("amount");

        MockERC20 collateral = MockERC20(collaterals[0].tokenAddress);

        vm.prank(caller);
        collateral.approve(address(dscEngine), amount);
        (bool success,) = address(collateral).call(
            abi.encodeWithSelector(dscEngine.depositCollateral.selector, address(collateral), 0)
        );

        assertEq(success, false, "Expected revert");
    }

    function check_depositCollateral_revertsWithUnapprovedCollateral() external {
        address caller = svm.createAddress("caller");
        uint256 amount = svm.createUint256("amount");
        uint8 decimals = uint8(svm.createUint256("decimals"));

        MockERC20 testToken = new MockERC20("Test", "TST", decimals);
        testToken.mint(caller, amount);

        vm.prank(caller);
        (bool success,) = address(testToken).call(
            abi.encodeWithSelector(dscEngine.depositCollateral.selector, address(testToken), amount)
        );

        assertEq(success, false, "Expected revert");
    }

    // / @custom:halmos --loop 4
    // Not enough, won't work because too much looping I guess
    function check_depositCollateral_canDepositCollateralAndGetAccountInfo() external {
        address caller = svm.createAddress("caller");
        uint256 amount = svm.createUint256("amountHere");
        MockERC20 collateral = MockERC20(collaterals[0].tokenAddress);

        vm.startPrank(caller);
        collateral.approve(address(dscEngine), amount);
        dscEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(caller);
        uint256 expectedDepositAmount =
            dscEngine.getAccountCollateralValueFromUsd(address(collateral), collateralValueInUsd);

        assertEq(totalDscMinted, 0, "Incorrect total DSC minted");
        assertEq(expectedDepositAmount, amount, "Incorrect collateral value");
    }
}

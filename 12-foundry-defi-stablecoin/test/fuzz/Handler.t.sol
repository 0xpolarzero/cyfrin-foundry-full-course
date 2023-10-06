// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    MockV3Aggregator ethUsdPriceFeed;
    // ...

    // Don't use uint256 as it could hit the absolute top, which would make other calls fail
    // in an unrealistic way
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    DSCEngine.Collateral[] collaterals;

    address[] hasDepositedCollateral;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        (DSCEngine.Collateral[] memory collateralArray,) = _config.getActiveNetworkConfig();
        for (uint256 i = 0; i < collateralArray.length; i++) {
            collaterals.push(collateralArray[i]);
        }

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(collaterals[0].tokenAddress)));
        // ...
    }

    function mintDsc(uint256 _amount, uint256 _addressSeed) external {
        // Get an address that has deposited, otherwise it will most probably never be an address that deposited interacting here again
        if (hasDepositedCollateral.length == 0) return;
        address sender = hasDepositedCollateral[_addressSeed % hasDepositedCollateral.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);

        int256 maxDscToMint = int256(collateralValueInUsd / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) return;

        uint256 amount = bound(_amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;

        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

    /// @dev _collateralSeed will pick a collateral among authorized ones
    function depositCollateral(uint256 _collateralSeed, uint256 _amountCollateral) external {
        // Get an allowed collateral
        MockERC20 collateral = _getCollateralFromSeed(_collateralSeed);
        // Bound the amount to avoid overflow later
        uint256 amountCollateralBounded = bound(_amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        // Mint, approve, THEN deposit
        collateral.mint(msg.sender, amountCollateralBounded);
        collateral.approve(address(dscEngine), amountCollateralBounded);
        dscEngine.depositCollateral(address(collateral), amountCollateralBounded);
        vm.stopPrank();

        hasDepositedCollateral.push(address(collateral));
    }

    function redeemCollateral(uint256 _collateralSeed, uint256 _amountCollateral) external {
        // Get an allowed collateral
        MockERC20 collateral = _getCollateralFromSeed(_collateralSeed);
        // Get the max amount of collateral that can be redeemed
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        // Scale the amount to redeem to avoid overflow later
        uint256 amountCollateralBounded = bound(_amountCollateral, 0, maxCollateralToRedeem);

        // ! Not working -> stops the whole test
        // vm.assume(amountCollateralBounded != 0);
        if (amountCollateralBounded == 0) return;

        dscEngine.redeemCollateral(address(collateral), amountCollateralBounded);
    }

    function updateCollateralPrice(uint96 newPrice) external {
        int256 newPriceInt = int256(uint256(newPrice));
        ethUsdPriceFeed.updateAnswer(newPriceInt);
    }

    function _getCollateralFromSeed(uint256 _collateralSeed) internal view returns (MockERC20) {
        return MockERC20(collaterals[_collateralSeed % 2].tokenAddress);
    }
}

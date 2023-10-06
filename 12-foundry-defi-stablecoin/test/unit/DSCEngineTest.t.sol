// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Utils} from "../../src/libraries/Utils.sol";

contract DSCEngineTest is Test {
    /* -------------------------------- CONTRACTS ------------------------------- */
    DeployDSCEngine private deployer;
    HelperConfig private config;
    DecentralizedStableCoin private dsc;
    DSCEngine private dscEngine;

    /* -------------------------------- CONSTANTS ------------------------------- */
    uint256 public constant PRICE_ETH_USD = 2_000;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant INITIAL_ERC20_BALANCE = 10 ether;

    uint256 public constant DECIMALS_WETH = 18;
    uint256 public constant DECIMALS_WBTC = 8;

    /* -------------------------------- VARIABLES ------------------------------- */
    address public USER = makeAddr("user");

    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    DSCEngine.Collateral[] public collaterals;

    /* -------------------------------------------------------------------------- */
    /*                                     SETUP                                  */
    /* -------------------------------------------------------------------------- */

    function setUp() external {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run();

        (DSCEngine.Collateral[] memory _collaterals,) = config.getActiveNetworkConfig();
        weth = _collaterals[0].tokenAddress;
        ethUsdPriceFeed = _collaterals[0].priceFeedAddress;
        wbtc = _collaterals[1].tokenAddress;
        wbtcUsdPriceFeed = _collaterals[1].priceFeedAddress;

        MockERC20(weth).mint(USER, INITIAL_ERC20_BALANCE);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 PRICE FEEDS                                */
    /* -------------------------------------------------------------------------- */

    function testGetUsdValue() external {
        uint256 ethAmount = 10 ether;
        uint256 expectedUsdValue = ethAmount * PRICE_ETH_USD; // 20,000 USD

        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(actualUsdValue, expectedUsdValue, "Incorrect USD value");
    }

    function testGetAccountCollateralValueFromUsd() external {
        uint256 usdAmount = 100;
        uint256 expectedWethCollateralValue = usdAmount / PRICE_ETH_USD; // 0.05 ETH
        uint256 actualWethCollateralValue = dscEngine.getAccountCollateralValueFromUsd(weth, usdAmount);

        assertEq(actualWethCollateralValue, expectedWethCollateralValue, "Incorrect WETH collateral value");
    }

    /* -------------------------------------------------------------------------- */
    /*                              depositCollateral                             */
    /* -------------------------------------------------------------------------- */

    function testRevertsIfCollateralZero() external {
        vm.startPrank(USER);

        MockERC20(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(Utils.ZeroValueNotAllowed.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() external {
        MockERC20 testToken = new MockERC20("Test", "TST", 18);
        testToken.mint(USER, 100 ether);

        vm.startPrank(USER);
        vm.expectRevert(Utils.ZeroAddressNotAllowed.selector);
        dscEngine.depositCollateral(address(testToken), 100 ether);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() external depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        assertEq(totalDscMinted, 0, "Incorrect total DSC minted");
        uint256 expectedDepositAmount = dscEngine.getAccountCollateralValueFromUsd(weth, collateralValueInUsd);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL, "Incorrect collateral value");
    }
}

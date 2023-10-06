// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin public dsc;

    address public constant USER = address(1);

    uint256 slot0;
    uint256 varr = 1;

    function setUp() external {
        vm.deal(USER, 10 ether);
        vm.prank(USER);
        // vm.startBroadcast();
        dsc = new DecentralizedStableCoin();
        // vm.stopBroadcast();
    }
}

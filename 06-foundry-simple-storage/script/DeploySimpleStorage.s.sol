// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {SimpleStorage} from "../src/SimpleStorage.sol";

contract DeploySimpleStorage is Script {
    function run() external returns (SimpleStorage simpleStorage) {
        // Won't be sent; computed before
        // ...
        vm.startBroadcast();
        // Will be computed/sent along with the transaction

        simpleStorage = new SimpleStorage();
        vm.stopBroadcast();
    }
}

// 0x34A1D3fff3958843C43aD80F30b94c510645C316

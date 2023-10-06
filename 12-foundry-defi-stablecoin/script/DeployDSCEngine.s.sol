// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDSCEngine is Script {
    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        // Get the config for the active network
        HelperConfig config = new HelperConfig();
        (DSCEngine.Collateral[] memory collaterals,) = config.getActiveNetworkConfig();

        vm.startBroadcast();

        // Deploy DSC and DSC Engine
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(collaterals, address(dsc));

        // Transfer ownership of DSC to DSC Engine
        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dsc, dscEngine, config);
    }
}

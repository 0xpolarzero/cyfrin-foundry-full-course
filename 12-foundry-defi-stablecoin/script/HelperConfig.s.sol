// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        DSCEngine.Collateral[] collaterals;
        uint256 deployerKey;
    }

    NetworkConfig private activeNetworkConfig;

    /// @dev Mock constants for price feeds
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2_000e8;
    int256 public constant BTC_USD_PRICE = 30_000e8;

    uint256 public constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        DSCEngine.Collateral[] memory collaterals = new DSCEngine.Collateral[](2);

        if (block.chainid == 11155111) {
            NetworkConfig memory sepoliaEthConfig = getSepoliaEthConfig();
            activeNetworkConfig.deployerKey = sepoliaEthConfig.deployerKey;
            collaterals = sepoliaEthConfig.collaterals;
        } else {
            NetworkConfig memory anvilEthConfig = getAnvilEthConfig();
            activeNetworkConfig.deployerKey = anvilEthConfig.deployerKey;
            collaterals = anvilEthConfig.collaterals;
        }

        for (uint256 i = 0; i < collaterals.length; i++) {
            activeNetworkConfig.collaterals.push(collaterals[i]);
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        DSCEngine.Collateral[] memory collaterals = new DSCEngine.Collateral[](2);
        collaterals[0] = DSCEngine.Collateral(
            // WETH
            0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            // ETH/USD price feed
            0x694AA1769357215DE4FAC081bf1f309aDC325306,
            // Decimals
            18
        );
        collaterals[1] = DSCEngine.Collateral(
            // WBTC
            0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            // BTC/USD price feed
            0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            // Decimals
            8
        );

        return NetworkConfig({collaterals: collaterals, deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.collaterals.length != 0) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockERC20 wethMock = new MockERC20("Wrapped Ether", "WETH", 18);
        wethMock.mint(msg.sender, 1_000e18);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        MockERC20 wbtcMock = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        wbtcMock.mint(msg.sender, 1_000e18);

        vm.stopBroadcast();

        // Prepare collaterals (WETH and WBTC)
        DSCEngine.Collateral[] memory collaterals = new DSCEngine.Collateral[](2);
        collaterals[0] = DSCEngine.Collateral(address(wethMock), address(ethUsdPriceFeed), 18);
        collaterals[1] = DSCEngine.Collateral(address(wbtcMock), address(btcUsdPriceFeed), 8);

        return NetworkConfig({collaterals: collaterals, deployerKey: ANVIL_DEPLOYER_KEY});
    }

    function getActiveNetworkConfig() external view returns (DSCEngine.Collateral[] memory, uint256) {
        return (activeNetworkConfig.collaterals, activeNetworkConfig.deployerKey);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
// import {console} from "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 3400e8; // $3,400
    int256 public constant BTC_USD_PRICE = 100000e8; // $100,000

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH/USD Sepolia
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC/USD Sepolia
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // WETH Sepolia
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063 // WBTC Sepolia (example)
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If we already deployed mocks, return existing config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // Deploy mock price feeds
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

        ERC20Mock wethErc20Mock = new ERC20Mock();
        ERC20Mock wbtcErc20Mock = new ERC20Mock();
        wethErc20Mock.mint(address(ethUsdPriceFeed), 100e18);
        vm.stopBroadcast();

        // For Anvil, we'll use the same addresses as mock tokens
        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethErc20Mock),
            wbtc: address(wbtcErc20Mock)
        });
    }
}

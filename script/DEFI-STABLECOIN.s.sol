// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DefiStableCoin} from "../src/DEFI-STABLECOIN.sol";
import {HelperConfig} from "./DSC_HELPER-CONFIG.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";

contract deployDSC is Script {
    string private name = "NUMI TOKEN";
    string private symbol = "NUMI";

    function run() external returns (DefiStableCoin, DSCEngine) {
        return deployDefiSC();
    }

    function deployDefiSC() internal returns (DefiStableCoin, DSCEngine) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc) = config.activeNetworkConfig();

        vm.startBroadcast();
        DefiStableCoin dsc = new DefiStableCoin(name, symbol, msg.sender);
        address dscAddress = address(dsc);
        DSCEngine dscEngine = new DSCEngine([weth, wbtc], [wethUsdPriceFeed, wbtcUsdPriceFeed], dscAddress);
        vm.stopBroadcast();

        return (dsc, dscEngine);
    }
}

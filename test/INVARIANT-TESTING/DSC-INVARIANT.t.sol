// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DefiStableCoin} from "../../src/DEFI-STABLECOIN.sol";
import {deployDSC} from "../../script/DEFI-STABLECOIN.s.sol";
import {HelperConfig} from "../../script/DSC_HELPER-CONFIG.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {dscHandler} from "./HANDLER.t.sol";

/* INVARIANT:
      - Total value of Collateral Deposited must be greater than Total DSC Minted
      - Getter View Functions should never revert <= Evergreen invariant
*/

contract dscInvariantTest is StdInvariant, Test {
    DefiStableCoin private dsc;
    DSCEngine private dscEngine;
    HelperConfig.NetworkConfig private config;
    dscHandler private handler;
    uint256 private constant MAX_THRESHOLD = 1500000000000000000;
    uint256 private constant MIN_THRESHOLD = 1200000000000000000;

    function setUp() external {
        deployDSC deploy = new deployDSC();
        (dsc, dscEngine) = deploy.run();
        dsc.transferOwnership(address(dscEngine));

        if (block.chainid == 31337) {
            config = HelperConfig.NetworkConfig({
                wethUsdPriceFeed: dscEngine.getPriceFeed(dscEngine.getTokenAddress(0)),
                wbtcUsdPriceFeed: dscEngine.getPriceFeed(dscEngine.getTokenAddress(1)),
                weth: dscEngine.getTokenAddress(0),
                wbtc: dscEngine.getTokenAddress(1)
            });

            handler = new dscHandler(dsc, dscEngine);
            targetContract(address(handler));

            bytes4[] memory selector = new bytes4[](1);
            selector[0] = handler.randomSelector.selector;
            targetSelector(FuzzSelector({addr: address(handler), selectors: selector}));
        }
    }

    function invariant_PROTOCOL_MUST_HAVE_MORE_COLLATERAL_VALUE_THAN_DSC_TOTAL_SUPPLY() public view {
        uint256 totalWethDeposited = ERC20Mock(config.weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = ERC20Mock(config.wbtc).balanceOf(address(dscEngine));
        uint256 totalDscSupply = dsc.totalSupply();

        uint256 wethValue = dscEngine.getCollateralValue(config.wethUsdPriceFeed, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getCollateralValue(config.wbtcUsdPriceFeed, totalWbtcDeposited);

        console.log(wethValue);
        console.log(wbtcValue);
        console.log(totalDscSupply);

        assert(wethValue + wbtcValue >= totalDscSupply);
    }

    function invariant_TOTAL_DSC_OF_ALL_USERS_IS_EQUAL_TO_THE_TOTAL_DSC_SUPPLY() public view {
        uint256 totalUserDSC;
        uint256 usersCount = dscEngine.getUsersCount();
        for (uint256 i = 0; i < usersCount; i++) {
            address user = dscEngine.getUsers(i);
            uint256 getDSCBalance = dscEngine.getUserMintedDscBalance(user);
            totalUserDSC += getDSCBalance;
        }

        uint256 totalSupply = dsc.totalSupply();
        assert(totalUserDSC == totalSupply);

        console.log("total DSC Supply: ", totalSupply);
        console.log("total User Supply: ", totalUserDSC);
    }

    function invariant_TOTAL_DEPOSIT_COLLATERAL_IS_EQUAL_TO_STORED_COLLATERAL_RECORD() public view {}

    function invariant_TEST_ALL_GETTERS() public view {
        dscEngine.getPriceFeed(dscEngine.getTokenAddress(0));
        dscEngine.getPriceFeed(dscEngine.getTokenAddress(1));

        dscEngine.getTokenAddress(0);
        dscEngine.getTokenAddress(1);

        uint256 usersCount = dscEngine.getUsersCount();
        for (uint256 i = 0; i < usersCount; i++) {
            address users = dscEngine.getUsers(i);
            dscEngine.getUserCollateralBalance(users, dscEngine.getTokenAddress(0));
            dscEngine.getUserCollateralBalance(users, dscEngine.getTokenAddress(1));
            dscEngine.getUserMintedDscBalance(users);
            dscEngine.getTokenToMintedDSC(users, config.weth);
            dscEngine.getTokenToMintedDSC(users, config.wbtc);
        }

        dscEngine.getDSCAddress();
    }
}

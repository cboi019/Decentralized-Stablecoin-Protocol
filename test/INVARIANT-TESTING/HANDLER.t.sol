// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DefiStableCoin} from "../../src/DEFI-STABLECOIN.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract dscHandler is StdInvariant, Test {
    DefiStableCoin private dsc;
    DSCEngine private dscEngine;

    address private weth;
    address private wbtc;
    address[] private users;
    uint256 private constant MAX_AMOUNT = type(uint64).max;
    uint256 private constant MAX_AMOUNT_DSC = type(uint16).max;
    uint256 private constant MAX_THRESHOLD = 1500000000000000000;
    uint256 private constant MIN_THRESHOLD = 1200000000000000000;
    uint256 private recordCalls;
    address private ethPriceFeed;
    address private btcPriceFeed;
    mapping(address users => mapping(address token => bool)) private s_ALREADY_FUNDED;

    constructor(DefiStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        weth = dscEngine.getTokenAddress(0);
        wbtc = dscEngine.getTokenAddress(1);

        ethPriceFeed = dscEngine.getPriceFeed(weth);
        btcPriceFeed = dscEngine.getPriceFeed(wbtc);
    }

    // this is the targeted function
    function randomSelector(
        uint256 _randomness,
        address _users,
        uint256 _token,
        uint256 _amount,
        uint256 _userIndex,
        uint256 _liquidatorIndex,
        uint256 _tokenIndex,
        uint96 _price
    ) public {
        uint256 selector = _randomness % 100;

        if (selector < 25) {
            liquidate(_liquidatorIndex, _tokenIndex);
        } else if (selector < 50) {
            depositCollateral(_users, _token, _amount);
        } else if (selector < 65) {
            mintDsc(_tokenIndex, _amount);
        } else if (selector < 85) {
            redeemCollateral(_token, _userIndex, _amount);
        } else {
            simulateEthPriceChange(_price);
        }
    }

    function depositCollateral(address _users, uint256 _token, uint256 _amount) public {
        vm.assume(_users != address(0));

        address token = _getTokenAddress(_token);
        vm.startPrank(_users);
        uint256 amountToApprove = MAX_AMOUNT / 2;
        if (ERC20Mock(token).balanceOf(_users) > amountToApprove) {
            ERC20Mock(token).approve(address(dscEngine), amountToApprove);
        } else {
            ERC20Mock(token).mint(_users, MAX_AMOUNT);
            ERC20Mock(token).approve(address(dscEngine), amountToApprove);
        }
        _amount = bound(_amount, 1, amountToApprove);
        try dscEngine.depositCollateral(token, _amount) {
            if (!s_ALREADY_FUNDED[_users][token]) {
                users.push(_users);
                s_ALREADY_FUNDED[_users][token] = true;
            }
        } catch {}
        vm.stopPrank();

        recordCalls++;
        console.log("depsoit: ", recordCalls);
    }

    function mintDsc(uint256 _tokenIndex, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_AMOUNT_DSC);

        address token = _getTokenAddress(_tokenIndex);

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            (, uint256 totalCollateralValue) = dscEngine.getUserAccountInfo(token, users[i]);

            if (totalCollateralValue == 0) {
                continue; // Skip users with no collateral
            }
            (uint256 info,) = dscEngine.getHealth(token, user, _amount);
            if (info >= MAX_THRESHOLD) {
                vm.prank(user);
                try dscEngine.mintDSC(token, _amount) {} catch {}
                vm.stopPrank();
            }
        }
    }

    function redeemCollateral(uint256 _token, uint256 userIndex, uint256 _amount) public {
        address tokenAddress = _getTokenAddress(_token);

        if (users.length > 0) {
            address user = users[userIndex % users.length];
            uint256 userEthBalance = dscEngine.getUserCollateralBalance(user, tokenAddress);
            _amount = bound(_amount, 0, userEthBalance);
            if (_amount > 0) {
                vm.startPrank(user);
                try dscEngine.redeemCollateral(tokenAddress, _amount) {} catch {}
                vm.stopPrank();
            }
        }
        recordCalls++;
        console.log("redeem: ", recordCalls);
    }

    function liquidate(uint256 _liquidatorIndex, uint256 _tokenIndex) public {
        address[2] memory token = [weth, wbtc];
        address tokenSelected = token[_tokenIndex % token.length];

        if (tokenSelected == weth) {
            for (uint256 i = 0; i < users.length; i++) {
                address user = users[i];
                uint256 userTotalDsc = dscEngine.getTokenToMintedDSC(user, weth);
                if (userTotalDsc == 0) continue;
                uint256 userWethDeposit = dscEngine.getUserCollateralBalance(user, weth);
                if (userWethDeposit != 0) {
                    if (users.length > 0) {
                        address liquidator = users[_liquidatorIndex % users.length];
                        uint256 liquidatorWethDeposit = dscEngine.getUserCollateralBalance(liquidator, weth);
                        if (liquidatorWethDeposit != 0 && liquidator != user) {
                            vm.startPrank(liquidator);
                            try dscEngine.liquidate(weth, user, userTotalDsc / 2) {} catch {}
                            vm.stopPrank();
                        }
                    }
                }
            }
        } else if (tokenSelected == wbtc) {
            for (uint256 i = 0; i < users.length; i++) {
                address user = users[i];
                uint256 userTotalDsc = dscEngine.getTokenToMintedDSC(user, wbtc);
                if (userTotalDsc == 0) continue;
                uint256 userWbtcDeposit = dscEngine.getUserCollateralBalance(user, wbtc);
                if (userWbtcDeposit != 0) {
                    if (users.length > 0) {
                        address liquidator = users[_liquidatorIndex % users.length];
                        uint256 liquidatorWbtcDeposit = dscEngine.getUserCollateralBalance(liquidator, wbtc);
                        if (liquidatorWbtcDeposit != 0 && liquidator != user) {
                            vm.startPrank(liquidator);
                            try dscEngine.liquidate(wbtc, user, userTotalDsc / 2) {} catch {}
                            vm.stopPrank();
                        }
                    }
                }
            }
        }
    }

    function simulateEthPriceChange(uint96 _price) public {
        uint256 maxPrice = 3400e8;
        uint256 NEW_ETH_PRICE = bound(uint256(_price), uint256(int256(1500e8)), maxPrice);
        console.log(NEW_ETH_PRICE);

        MockV3Aggregator(ethPriceFeed).updateAnswer(int256(NEW_ETH_PRICE));

        uint256 maxPrice1 = 20000e8;
        uint256 NEW_BTC_PRICE = bound(uint256(_price), uint256(int256(15554e8)), maxPrice1);
        console.log(NEW_BTC_PRICE);

        MockV3Aggregator(btcPriceFeed).updateAnswer(int256(NEW_BTC_PRICE));
    }

    //======================//
    //    HELPER FUNCTION   //
    //======================//
    function _getTokenAddress(uint256 _tokenIndex) internal view returns (address) {
        return (_tokenIndex % 2 == 0) ? weth : wbtc;
    }
}

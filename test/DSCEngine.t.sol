// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DefiStableCoin} from "../src/DEFI-STABLECOIN.sol";
import {deployDSC} from "../script/DEFI-STABLECOIN.s.sol";
import {HelperConfig} from "../script/DSC_HELPER-CONFIG.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {engineLibrary} from "../src/DSCLIB.sol";
import {Vm} from "forge-std/Vm.sol";

contract testDSCEngine is Test {
    DefiStableCoin private dsc;
    DSCEngine private dscEngine;
    HelperConfig.NetworkConfig private config;

    address private externalTokenAddress = makeAddr("Solana");
    uint256 private constant DEPOSIT_AMOUNT = 5e18;
    address private user1 = makeAddr("Charles");
    address private user2 = makeAddr("Buchi");
    address private liquidator = makeAddr("Dika");
    uint8 private constant DECIMALS = 8;
    uint256 private constant DSC_AMOUNT_TO_MINT = 8e21;
    uint256 private constant HEALTH_RISK_AMOUNT = 2e22;
    uint256 private constant HEALTH_GOOD_AMOUNT = 5e21;
    uint256 private constant HEALTH_WARNING_AMOUNT = 12e21;

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
        }
        ERC20Mock(config.weth).mint(user1, 10e18);
        ERC20Mock(config.weth).mint(liquidator, 10e18);
    }

    modifier userDepositsCollateral() {
        vm.startPrank(user1);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function test_DSC_IS_DEPLOYED() public view {
        assertEq(abi.encodePacked(dsc.name()), abi.encodePacked("NUMI TOKEN"));
        assertEq(abi.encodePacked(dsc.symbol()), abi.encodePacked("NUMI"));
        assertEq(dsc.owner(), address(dscEngine));
    }

    function test_TOKEN_ADDRESS_ARRAY_IS_UPDATED() public view {
        assertEq(dscEngine.getTokenAddress(0), config.weth);
        assertEq(dscEngine.getTokenAddress(1), config.wbtc);
    }

    function test_DSCENGINE_IS_DEPLOYED() public view {
        assertEq(dscEngine.getDSCAddress(), address(dsc));

        assertEq(dscEngine.getPriceFeed(config.weth), config.wethUsdPriceFeed);
        assertEq(dscEngine.getPriceFeed(config.wbtc), config.wbtcUsdPriceFeed);
    }

    function test_ONLY_ALLOWED_TOKEN_FOR_COLLATERAL(address _external) public {
        vm.assume(_external != config.weth && _external != config.wbtc);
        vm.expectRevert(DSCEngine.DSCEngine__NOT_ALLOWED_TOKEN.selector);
        dscEngine.depositCollateral(_external, DEPOSIT_AMOUNT);
    }

    function test_DEPOSIT_CANNOT_BE_ZERO() public {
        vm.expectRevert(DSCEngine.DSCEngine__INPUT_AN_AMOUNT.selector);
        dscEngine.depositCollateral(config.weth, 0);
    }

    function test_STATE_VARIBALES_UPDATE_AFTER_COLLATERAL_DEPOSIT_AND_EVENT_EMITTED() public {
        vm.prank(user1);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true, address(dscEngine));
        emit DSCEngine.CollateralDeposited(user1, config.weth, DEPOSIT_AMOUNT);

        vm.prank(user1);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT);

        uint256 balance = dscEngine.getUserCollateralBalance(user1, config.weth);
        assertEq(balance, DEPOSIT_AMOUNT);
    }

    function test_PRICE_FEED_ACCURACY() public view {
        uint256 amount = 5e17;
        (uint256 actualOutput,) = engineLibrary._getCollateralValue(config.wethUsdPriceFeed, amount);
        uint256 expectedOutput = 1700e18;

        assertEq(actualOutput, expectedOutput);
    }

    function test_GETTING_USER_ACCOUNT_INFO() public userDepositsCollateral {
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = dscEngine.getUserAccountInfo(config.weth, user1);

        assertEq(totalDSCMinted, 0);
        assertEq(totalCollateralValue, 1.7e22);
    }

    function test_MINT_REVERT() public userDepositsCollateral {
        // IF RISK
        vm.prank(user1);
        vm.expectRevert(DSCEngine.DSCEngine__HEALTH_AT_RISK.selector);
        dscEngine.mintDSC(config.weth, HEALTH_RISK_AMOUNT);

        // IF GOOD
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);

        uint256 balance = dscEngine.getTokenToMintedDSC(user1, config.weth);
        assertEq(balance, HEALTH_GOOD_AMOUNT);
    }

    function test_USER_CANNOT_REDEEDM_MORE_COLLATERAL_THAN_OWNED(uint256 _amount) public userDepositsCollateral {
        vm.assume(_amount > DEPOSIT_AMOUNT);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__INSUFFICIENT_BALANCE.selector, _amount));
        dscEngine.redeemCollateral(config.weth, _amount);
    }

    function test_REVERTS_IF_HEALTH_IS_AT_RISK() public userDepositsCollateral {
        uint256 amountToWithdraw = 3e18;
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, DSC_AMOUNT_TO_MINT);

        MockV3Aggregator(config.wethUsdPriceFeed).updateAnswer(1000e8);

        vm.prank(user1);
        vm.expectRevert(DSCEngine.DSCEngine__HEALTH_AT_RISK.selector);
        dscEngine.redeemCollateral(config.weth, amountToWithdraw);
    }

    function test_BURN_DSC_FUNCTION_REVERTS_AND_UPDATES_STATE_AS_EXPECTED(uint256 _amount)
        public
        userDepositsCollateral
    {
        uint256 amountToBurn = 3e21;
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, DSC_AMOUNT_TO_MINT);

        vm.prank(user1);
        vm.expectRevert(DSCEngine.DSCEngine__INPUT_AN_AMOUNT.selector);
        dscEngine.burnDSC(0, config.weth);

        uint256 userDscBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);
        vm.assume(_amount > userDscBalance);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__INSUFFICIENT_BALANCE.selector, _amount));
        dscEngine.burnDSC(_amount, config.weth);

        uint256 previousBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);
        vm.prank(user1);
        dscEngine.burnDSC(amountToBurn, config.weth);
        uint256 newBalance = previousBalance - amountToBurn;
        uint256 expectedBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);

        assertEq(expectedBalance, newBalance);
    }

    function test_DEPOSIT_COLLATERAL_FOR_DSC_WORKS_AS_EXPECTED() public {
        vm.startPrank(user1);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        dscEngine.depositCollateralForDSC(config.weth, DEPOSIT_AMOUNT, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        vm.startPrank(user1);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__HEALTH_AT_RISK.selector);
        dscEngine.depositCollateralForDSC(config.weth, DEPOSIT_AMOUNT, HEALTH_RISK_AMOUNT);
        vm.stopPrank();
    }

    function test_REDEEM_COLLATERAL_WITH_DSC_WORKS_AS_EXPECTED(uint256 _amount) public {
        vm.startPrank(user1);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        dscEngine.depositCollateralForDSC(config.weth, DEPOSIT_AMOUNT, DSC_AMOUNT_TO_MINT);
        uint256 dscBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);

        vm.assume(_amount > dscBalance);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__INSUFFICIENT_BALANCE.selector, _amount));
        dscEngine.redeemCollateralWithDSC(config.weth, DEPOSIT_AMOUNT, _amount);
        vm.stopPrank();

        vm.startPrank(user1);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        dscEngine.depositCollateralForDSC(config.weth, DEPOSIT_AMOUNT, DSC_AMOUNT_TO_MINT);
        dscEngine.redeemCollateralWithDSC(config.weth, DEPOSIT_AMOUNT, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
        console.log(dscEngine.getUserCollateralBalance(user1, config.weth));
    }

    function test_LIQUIDATION_REVERTS_IF_HEALTH_IS_GOOD() public userDepositsCollateral {
        // IF GOOD
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);

        vm.startPrank(liquidator);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT);
        dscEngine.mintDSC(config.weth, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        // (uint256 healthStatus, ) = dscEngine.getUsersHealthStatus(config.weth, user1);
        uint256 amountToBurn = dscEngine.getTokenToMintedDSC(user1, config.weth) / 2;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HEALTH_IS_GOOD.selector));
        vm.prank(liquidator);
        dscEngine.liquidate(config.weth, user1, amountToBurn);
    }

    function test_LIQUIDATION_REVERTS_IF_HEALTH_IS_IN_GRACE_ZONE() public userDepositsCollateral {
        // IF WARNING
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);

        vm.startPrank(liquidator);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT * 2);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT * 2);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);
        vm.stopPrank();

        MockV3Aggregator(config.wethUsdPriceFeed).updateAnswer(1354e8);

        // (uint256 healthStatus, ) = dscEngine.getUsersHealthStatus(config.weth, user1);
        uint256 amountToBurn = dscEngine.getTokenToMintedDSC(user1, config.weth) / 2;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HEALTH_AT_GRACE_ZONE.selector));
        vm.prank(liquidator);
        dscEngine.liquidate(config.weth, user1, amountToBurn);
    }

    function test_LIQUIDATOR_CANNOT_BURN_MORE_THAN_HALF_OF_DEBT(uint256 _amount) public userDepositsCollateral {
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);

        vm.startPrank(liquidator);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT * 2);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT * 2);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);
        vm.stopPrank();

        MockV3Aggregator(config.wethUsdPriceFeed).updateAnswer(1180e8);

        uint256 amountToBurn = dscEngine.getTokenToMintedDSC(user1, config.weth);
        vm.assume(_amount != amountToBurn / 2 && _amount > amountToBurn / 2);
        vm.expectRevert(DSCEngine.DSCEngine__CANNOT_BURN_MORE_THAN_HALF_OF_DEBT.selector);
        vm.prank(liquidator);
        dscEngine.liquidate(config.weth, user1, _amount);
    }

    function test_LIQUIDTION_IS_SUCCESSFUL() public userDepositsCollateral {
        // IF RISK
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);

        vm.startPrank(liquidator);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT * 2);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT * 2);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);
        vm.stopPrank();

        MockV3Aggregator(config.wethUsdPriceFeed).updateAnswer(1180e8);
        (, string memory status1) = dscEngine.getUsersHealthStatus(config.weth, user1);
        console.log(status1);

        uint256 amountToBurn = dscEngine.getTokenToMintedDSC(user1, config.weth) / 2;
        uint256 previousDebtorEthBalance = dscEngine.getUserCollateralBalance(user1, config.weth);
        uint256 previousDebtorDSCBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);
        uint256 previousLiquidatorDSCBalance = ERC20Mock(address(dsc)).balanceOf(liquidator);
        vm.prank(liquidator);
        dscEngine.liquidate(config.weth, user1, amountToBurn);

        uint256 newDebtorEthBalance = dscEngine.getUserCollateralBalance(user1, config.weth);
        uint256 newDebtorDSCBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);
        uint256 newLiquidatorDSCBalance = ERC20Mock(address(dsc)).balanceOf(liquidator);

        assert(newDebtorEthBalance < previousDebtorEthBalance);
        assert(newDebtorDSCBalance < previousDebtorDSCBalance);
        assert(newLiquidatorDSCBalance < previousLiquidatorDSCBalance);
    }

    function test_LIQUIDTION_REVERTS_IF_HEALTH_OF_LIQUIDATOR_WILL_BE_AT_RISK() public userDepositsCollateral {
        // IF RISK
        vm.prank(user1);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);

        vm.startPrank(liquidator);
        ERC20Mock(config.weth).approve(address(dscEngine), DEPOSIT_AMOUNT * 2);
        dscEngine.depositCollateral(config.weth, DEPOSIT_AMOUNT);
        dscEngine.mintDSC(config.weth, HEALTH_GOOD_AMOUNT);
        vm.stopPrank();

        MockV3Aggregator(config.wethUsdPriceFeed).updateAnswer(1180e8);

        uint256 amountToBurn = dscEngine.getTokenToMintedDSC(user1, config.weth) / 2;
        vm.prank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HEALTH_AT_RISK.selector);
        dscEngine.liquidate(config.weth, user1, amountToBurn);

        uint256 newDebtorEthBalance = dscEngine.getUserCollateralBalance(user1, config.weth);
        uint256 newDebtorDSCBalance = dscEngine.getTokenToMintedDSC(user1, config.weth);
        uint256 newLiquidatorDSCBalance = ERC20Mock(address(dsc)).balanceOf(liquidator);
        console.log(newDebtorDSCBalance);
        console.log(newDebtorEthBalance);
        console.log(newLiquidatorDSCBalance);
    }
}


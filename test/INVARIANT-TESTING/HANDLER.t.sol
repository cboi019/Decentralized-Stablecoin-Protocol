// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DefiStableCoin} from "../../src/DEFI-STABLECOIN.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * @title dscHandler
 * @notice Stateful fuzzing handler for DSC Engine invariant testing.
 *
 * @dev
 * This handler simulates realistic user actions interacting with the DSCEngine.
 * It performs:
 * - Deposits
 * - DSC mints
 * - Collateral redemptions
 * - Liquidations after price drops
 * - Oracle price changes
 *
 * It also tracks:
 * - Users added to the system
 * - DSC minted per user per token
 * - Token balances
 * - Price drop conditions
 *
 * The handler creates highly realistic scenarios used by Foundry’s invariant
 * framework to discover protocol-breaking behavior.
 */
contract dscHandler is StdInvariant, Test {
    /// @notice The deployed DefiStableCoin (DSC) contract.
    DefiStableCoin private dsc;
    /// @notice The deployed DSCEngine contract, which manages all collateral and minting logic.
    DSCEngine private dscEngine;

    /// @notice The address of the WETH token, used as collateral.
    address private weth;
    /// @notice The address of the WBTC token, used as collateral.
    address private wbtc;
    /// @notice Array of all unique addresses that have successfully interacted with the system (e.g., deposited collateral).
    address[] private users;
    /// @notice Maximum amount for collateral deposits/mints used for bounding fuzz input. Set to maximum of uint64.
    uint256 private constant MAX_AMOUNT = type(uint64).max;
    /// @notice Maximum amount for DSC minting used for bounding fuzz input. Set to maximum of uint64.
    uint256 private constant MAX_AMOUNT_DSC = type(uint64).max;
    /// @notice Maximum threshold for collateralization rate (150% scaled to 18 decimals). Not currently used in the handler logic.
    uint256 private constant MAX_THRESHOLD = 1500000000000000000;
    /// @notice Minimum threshold for collateralization rate (120% scaled to 18 decimals). Not currently used in the handler logic.
    uint256 private constant MIN_THRESHOLD = 1200000000000000000;
    /// @notice Counter to track the number of external calls made to the handler for monitoring.
    uint256 private recordCalls;

    /// @notice Address of the ETH MockV3Aggregator price feed contract.
    address private ethPriceFeed;
    /// @notice Address of the BTC MockV3Aggregator price feed contract.
    address private btcPriceFeed;

    /// @dev Tracks the *last* known price for a collateral token. Used to determine if a price drop has occurred for liquidation.
    mapping(address token => uint256 Price) private s_TOKEN_TO_OLD_PRICE;

    /// @dev Tracks how much DSC each user *successfully* minted for each token.
    mapping(address user => mapping(address token => uint256 mintedDSC)) private s_TOKEN_TO_MINTED_DSC;

    /// @dev Tracks whether a user has already successfully deposited collateral with a specific token at least once, used for populating the `users` array.
    mapping(address users => mapping(address token => bool)) private s_ALREADY_FUNDED;

    /**
     * @notice Initializes handler with deployed DSC and DSCEngine contracts.
     * @param _dsc The DSC token contract.
     * @param _dscEngine The DSCEngine that manages collateral logic.
     */
    constructor(DefiStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        weth = dscEngine.getTokenAddress(0);
        wbtc = dscEngine.getTokenAddress(1);

        ethPriceFeed = dscEngine.getPriceFeed(weth);
        btcPriceFeed = dscEngine.getPriceFeed(wbtc);
    }

    /**
     * @notice Entry point for Foundry’s invariant fuzzer. Picks a random action based on the input randomness.
     *
     * @dev The selector logic is weighted to favor general user activity (deposits and mints):
     * - `< 25`: `depositCollateral` (25% chance)
     * - `< 50`: `mintDsc` (25% chance)
     * - `< 70`: `redeemCollateral` (20% chance)
     * - `else` (70+): `simulateEthPriceChange` (30% chance - includes liquidation attempt)
     *
     * @param _randomness A large random number used to select the function to execute.
     * @param _users Random address used as the user for `depositCollateral`.
     * @param _token Random number used to select collateral token index (WETH/WBTC).
     * @param _amount Random number used to determine transaction amounts.
     * @param _userIndex Random number used to select a user from the `users` array for redemption.
     * @param _liquidatorIndex Random number used to select a liquidator address.
     * @param _tokenIndex Random number used to select a collateral token for minting.
     * @param _price Random number used to simulate new price feed data.
     */
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

        // Normal actions
        if (selector < 25) {
            depositCollateral(_users, _token, _amount);
        } else if (selector < 50) {
            mintDsc(_tokenIndex, _amount);
        } else if (selector < 70) {
            redeemCollateral(_token, _userIndex, _amount);
        } else {
            simulateEthPriceChange(_price, _liquidatorIndex);
        }
    }

    /**
     * @notice Simulates a user depositing collateral.
     * @dev Ensures the user has enough tokens (mints them if necessary), approves the DSCEngine,
     * bounds the deposit amount, and updates the internal `users` tracking array upon first successful deposit.
     * Uses `try/catch` to prevent the handler from reverting on failing deposits (e.g., zero amount, not approved token).
     * @param _users The address performing the deposit.
     * @param _token A random number used to select the token address (WETH or WBTC).
     * @param _amount A random amount that is bounded for the deposit.
     */
    function depositCollateral(address _users, uint256 _token, uint256 _amount) public {
        vm.assume(_users != address(0));

        address token = _getTokenAddress(_token);
        vm.startPrank(_users);

        uint256 amountToApprove = MAX_AMOUNT / 2;

        // Ensure user has enough balance to deposit and approve
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
        console.log("deposit: ", recordCalls);
    }

    /**
     * @notice Iterates through all tracked users and attempts to mint DSC.
     *
     * @dev Skips users without any collateral value. Mint amount is bounded.
     * Uses `try/catch` to absorb reverts from failed mints (e.g., insufficient collateral/max DSC minted).
     * NOTE: This function's implementation currently updates `s_TOKEN_TO_MINTED_DSC` regardless of whether the `try` block succeeds, which may lead to an inaccurate internal state if `mintDSC` reverts. This is left as-is per user request.
     * @param _tokenIndex A random number used to select the collateral token for minting.
     * @param _amount The random, bounded amount of DSC to attempt to mint.
     */
    function mintDsc(uint256 _tokenIndex, uint256 _amount) public {
        if (users.length == 0) return;
        _amount = bound(_amount, 1, MAX_AMOUNT_DSC);
        address token = _getTokenAddress(_tokenIndex);

        for (uint256 i = 0; i < users.length; i++) {
            address user = getUsers(i);

            (, uint256 totalCollateralValue) = dscEngine.getUserAccountInfo(token, user);

            if (totalCollateralValue == 0) continue;

            vm.prank(user);

            try dscEngine.mintDSC(token, _amount) {} catch {}
            vm.stopPrank();

            s_TOKEN_TO_MINTED_DSC[user][token] += _amount;
        }
    }

    /**
     * @notice Attempts to redeem collateral for a randomly selected user.
     *
     * @dev Selects a user from the `users` array based on `userIndex`.
     * Bounds the redemption amount by the user's actual collateral balance to ensure a realistic attempt.
     * Uses `try/catch` to absorb reverts from failed redemptions (e.g., health factor too low).
     * @param _token A random number used to select the collateral token.
     * @param userIndex A random index used to select a user from the `users` array.
     * @param _amount A random amount that is bounded by the user's current collateral.
     */
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

    /**
     * @notice Attempts to liquidate users ONLY when the price of the specified collateral token has fallen since the last check.
     *
     * @dev Checks `s_TOKEN_TO_OLD_PRICE` to determine if a price drop has occurred. If no price drop, it returns early.
     * If liquidation conditions are met, it iterates through all users, calculating a fixed burn amount (50% of total DSC minted).
     * It uses `try/catch` to absorb reverts if liquidation fails (e.g., user is not underwater, liquidator lacks DSC).
     * The liquidator is selected based on `_liquidatorIndex`.
     * @param _liquidatorIndex A random index used to select the address attempting liquidation.
     * @param _token The collateral token address (WETH or WBTC) to check and liquidate against.
     * @param _newPrice The newly set price for the collateral token.
     */
    function liquidate(uint256 _liquidatorIndex, address _token, uint256 _newPrice) public {
        uint256 oldPrice = s_TOKEN_TO_OLD_PRICE[_token];

        if (users.length == 0) return;
        if (oldPrice > 0) {
            if (_newPrice >= oldPrice) {
                return;
            }
        }

        for (uint256 i = 0; i < users.length; i++) {
            address user = getUsers(i);
            uint256 userTotalDsc = getTokenToMintedDSC(user, _token);
            if (userTotalDsc == 0) continue;
            uint256 dscToBurn = userTotalDsc / 2;

            uint256 userTokenDeposit = dscEngine.getUserCollateralBalance(user, _token);
            if (userTokenDeposit == 0) continue;

            address liquidator = getUsers(_liquidatorIndex % users.length);
            uint256 liquidatorDSCBalance = getTokenToMintedDSC(liquidator, _token);

            if (liquidatorDSCBalance >= dscToBurn && liquidator != user) {
                vm.startPrank(liquidator);
                try dscEngine.liquidate(_token, user, dscToBurn) {} catch {}
                vm.stopPrank();
            }
        }

        s_TOKEN_TO_OLD_PRICE[_token] = _newPrice;
    }

    /**
     * @notice Simulates price feed updates for ETH or BTC based on price parity, and triggers liquidation check.
     *
     * @dev If `_price` is even, it updates the ETH price feed. If odd, it updates the BTC price feed.
     * The price is bounded to realistic market ranges to avoid extreme fuzzing values.
     * This function calls `liquidate` immediately after updating the price.
     * @param _price The random price value (uint96) used to set the new oracle answer.
     * @param _liquidatorIndex A random index passed through to `liquidate` to select a liquidator.
     */
    function simulateEthPriceChange(uint96 _price, uint256 _liquidatorIndex) public {
        if (_price % 2 == 0) {
            uint256 maxPrice = 5000e8;
            uint256 NEW_ETH_PRICE = bound(uint256(_price), uint256(int256(1800e8)), maxPrice);

            console.log(NEW_ETH_PRICE);
            MockV3Aggregator(ethPriceFeed).updateAnswer(int256(NEW_ETH_PRICE));
            liquidate(_liquidatorIndex, weth, NEW_ETH_PRICE);
        } else {
            uint256 maxPrice1 = 120000e8;
            uint256 NEW_BTC_PRICE = bound(uint256(_price), uint256(int256(80554e8)), maxPrice1);

            console.log(NEW_BTC_PRICE);
            MockV3Aggregator(btcPriceFeed).updateAnswer(int256(NEW_BTC_PRICE));
            liquidate(_liquidatorIndex, wbtc, NEW_BTC_PRICE);
        }
    }

    //======================//
    //  HELPER FUNCTIONS    //
    //======================//

    /// @notice Returns the user address at a given index in the tracked `users` array.
    /// @param _index The index of the user in the array.
    /// @return The address of the user.
    function getUsers(uint256 _index) public view returns (address) {
        return users[_index];
    }

    /// @notice Returns the total number of unique users tracked by the handler.
    /// @return The length of the `users` array.
    function getUsersCount() public view returns (uint256) {
        return users.length;
    }

    /// @notice Returns the total DSC amount minted by a specific user associated with a specific collateral token.
    /// @param _user The address of the user.
    /// @param _token The address of the collateral token.
    /// @return The amount of DSC tracked as minted.
    function getTokenToMintedDSC(address _user, address _token) public view returns (uint256) {
        return s_TOKEN_TO_MINTED_DSC[_user][_token];
    }

    /// @notice Helper to select either WETH or WBTC based on index parity.
    /// @dev If `_tokenIndex` is even, returns WETH; if odd, returns WBTC.
    /// @param _tokenIndex The random index used for selection.
    /// @return The address of the selected collateral token.
    function _getTokenAddress(uint256 _tokenIndex) internal view returns (address) {
        return (_tokenIndex % 2 == 0) ? weth : wbtc;
    }
}
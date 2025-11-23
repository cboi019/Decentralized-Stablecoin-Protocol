// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {DefiStableCoin} from "./DEFI-STABLECOIN.sol";
import {OracleLib} from "./ORACLE-LIB.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Charles Onyii
 * @notice Decentralized Stablecoin Engine with collateral-specific debt tracking
 * @dev This protocol implements a novel approach to stablecoin minting where debt is allocated to specific collateral types,
 * preventing protocol insolvency through granular health checks at both user and protocol levels.
 *
 * Key Features:
 * - Collateral-specific DSC minting (prevents cross-collateral insolvency)
 * - Dual health checks (user-level and protocol-level)
 * - Liquidation with grace period (120-150% collateralization)
 * - Forward-looking health validation (checks if transaction will break health)
 * - Oracle staleness protection via OracleLib
 *
 * The system supports WETH and WBTC as collateral with Chainlink price feeds.
 */
contract DSCEngine {
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__TOKEN_ADDRESSES_AND_PRICE_FEED_ADDRESSES_MUST_BE_SAME_LENGTH();
    error DSCEngine__NOT_ALLOWED_TOKEN();
    error DSCEngine__INPUT_AN_AMOUNT();
    error DSCEngine__INSUFFICIENT_BALANCE(uint256);
    error DSCEngine__TRANSACTION_FAILED();
    error DSCEngine__HEALTH_AT_RISK();
    error DSCEngine__NO_COLLATERAL_DEPOSITED();
    error DSCEngine__HEALTH_IS_GOOD(uint256);
    error DSCEngine__HEALTH_AT_GRACE_ZONE(uint256);
    error DSCEngine__CANNOT_BURN_MORE_THAN_HALF_OF_DEBT();
    error DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
    error DSCEngine__NOT_ENOUGH_DEBT_TO_BURN();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of allowed collateral token addresses
    address[] private s_TOKEN_ADDRESSES;

    /// @notice Array of users who have deposited (used for invariant testing)
    address[] private s_USERS;

    /// @notice Maximum health threshold (150% = 1.5e18) - below this triggers liquidation eligibility
    uint256 private constant s_MAX_THRESHOLD = 1500000000000000000;

    /// @notice Minimum health threshold (120% = 1.2e18) - grace zone between min and max
    uint256 private constant s_MIN_THRESHOLD = 1200000000000000000;

    /// @notice Precision for calculations (1e18)
    uint256 private constant s_PRECISION = 1e18;

    /// @notice Divisor for calculating half of debtor's balance during liquidation
    uint256 private constant s_HALF_OF_DEBTORS_BALANCE = 2;

    /// @notice Tracks which tokens are allowed as collateral
    mapping(address tokenAddreses => bool) private isAllowed;

    /// @notice Total DSC minted by each user across all collateral types
    mapping(address user => uint256 mintedDSC) private s_USER_MINTED_DSC;

    /// @notice Maps collateral token addresses to their Chainlink price feed addresses
    mapping(address tokenAddress => address priceFeed) private s_TOKEN_AND_PRICE_FEED;

    /// @notice Tracks if a user has already deposited (prevents duplicate user entries)
    mapping(address users => bool) private s_ALREADY_FUNDED;

    /// @notice Maps user address and collateral token to DSC minted against that specific collateral
    /// @dev This prevents cross-collateral insolvency - DSC is allocated to specific collateral
    mapping(address user => mapping(address token => uint256 mintedDSC)) private s_TOKEN_TO_MINTED_DSC;

    /// @notice Maps user address and collateral token to deposited collateral amount
    mapping(address user => mapping(address tokenAddress => uint256 collateral)) private s_USERS_COLLATERAL_BALANCE;

    /// @notice The DSC stablecoin contract
    DefiStableCoin private immutable i_DSC;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures only allowed collateral tokens can be used
     * @param _tokenAddress The token address to validate
     */
    modifier onlyAllowedAddress(address _tokenAddress) {
        _onlyAllowedAddress(_tokenAddress);
        _;
    }

    /**
     * @notice Ensures amount is greater than zero
     * @param _amount The amount to validate
     */
    modifier noneZero(uint256 _amount) {
        _noneZero(_amount);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
    event mintedDSC(address indexed user, uint256 amount);
    event DSCBurned(address indexed user, uint256 amount);
    event liqudated(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the DSC Engine with collateral tokens and price feeds
     * @param _tokenAddresses Array of allowed collateral token addresses [WETH, WBTC]
     * @param _priceFeedAddresses Array of Chainlink price feed addresses corresponding to tokens
     * @param _dscAddress Address of the DefiStableCoin contract
     * @dev Token addresses and price feed addresses must be in the same order
     */
    constructor(address[2] memory _tokenAddresses, address[2] memory _priceFeedAddresses, address _dscAddress) {
        if (_priceFeedAddresses.length != _tokenAddresses.length) {
            revert DSCEngine__TOKEN_ADDRESSES_AND_PRICE_FEED_ADDRESSES_MUST_BE_SAME_LENGTH();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_TOKEN_AND_PRICE_FEED[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_TOKEN_ADDRESSES.push(_tokenAddresses[i]);
            isAllowed[_tokenAddresses[i]] = true;
        }
        i_DSC = DefiStableCoin(_dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits collateral and mints DSC in one transaction
     * @param _tokenAddress The collateral token to deposit (WETH or WBTC)
     * @param _collateralAmount Amount of collateral to deposit
     * @param _dscAmount Amount of DSC to mint against the deposited collateral
     * @dev This is a convenience function that combines depositCollateral and mintDSC
     */
    function depositCollateralForDSC(address _tokenAddress, uint256 _collateralAmount, uint256 _dscAmount) external {
        depositCollateral(_tokenAddress, _collateralAmount);
        mintDSC(_tokenAddress, _dscAmount);
    }

    /**
     * @notice Burns DSC and redeems collateral in one transaction
     * @param _tokenAddress The collateral token to redeem
     * @param _collateralAmount Amount of collateral to redeem
     * @param _dscAmount Amount of DSC to burn
     * @dev Burns DSC first to improve health before attempting withdrawal
     */
    function redeemCollateralWithDSC(address _tokenAddress, uint256 _collateralAmount, uint256 _dscAmount) external {
        burnDSC(_dscAmount, _tokenAddress);
        redeemCollateral(_tokenAddress, _collateralAmount);
    }

    /**
     * @notice Liquidates an undercollateralized position
     * @param _tokenAddress The collateral token to seize
     * @param _debtor The address of the user being liquidated
     * @param _dscToBurn Amount of DSC to burn (max 50% of debtor's total debt)
     * @dev Liquidation is only allowed when health is below 120% and above 150%
     * @dev Liquidator receives 110% of collateral value (10% bonus)
     * @dev Prevents liquidator from becoming undercollateralized after liquidation
     */
    function liquidate(address _tokenAddress, address _debtor, uint256 _dscToBurn)
        external
        onlyAllowedAddress(_tokenAddress)
        noneZero(_dscToBurn)
    {
        // 1) Health checks - ensure debtor is liquidatable
        uint256 healthStatus = getHealthStatusForLiquidation(_tokenAddress, _debtor);
        if (healthStatus >= s_MAX_THRESHOLD) {
            revert DSCEngine__HEALTH_IS_GOOD(healthStatus);
        }
        if (healthStatus < s_MAX_THRESHOLD && healthStatus >= s_MIN_THRESHOLD) {
            revert DSCEngine__HEALTH_AT_GRACE_ZONE(healthStatus);
        }

        // 2) Compute allowed maximum (50% of debt to prevent full liquidation)
        uint256 maxAllowedToBurn = getTokenToMintedDSC(_debtor, _tokenAddress) / 2;
        if (_dscToBurn > maxAllowedToBurn) {
            revert DSCEngine__CANNOT_BURN_MORE_THAN_HALF_OF_DEBT();
        }

        // 3) Check liquidator has sufficient DSC balance
        uint256 liquidatorDscBalance = i_DSC.balanceOf(msg.sender);
        if (liquidatorDscBalance < _dscToBurn) {
            revert DSCEngine__INSUFFICIENT_BALANCE(liquidatorDscBalance);
        }

        // 4) Get current collateral price from oracle
        address collateralPriceFeed = getPriceFeed(_tokenAddress);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralPriceFeed);
        (, int256 answer,,,) = priceFeed.roundDataStaleCheck();
        if (answer <= 0) revert DSCEngine__TRANSACTION_FAILED();

        uint256 priceScaled = uint256(answer) * 1e10; // Scale to 1e18

        // 5) Calculate collateral to seize based on DSC amount
        uint256 collateralToSeize = (_dscToBurn * s_PRECISION) / priceScaled;

        // 6) Add 10% liquidation bonus
        uint256 bonus = (collateralToSeize * 10) / 100;
        uint256 totalSeize = collateralToSeize + bonus;

        // 7) Ensure debtor has enough collateral
        uint256 debtorCollateral = s_USERS_COLLATERAL_BALANCE[_debtor][_tokenAddress];
        if (debtorCollateral < totalSeize) {
            revert DSCEngine__INSUFFICIENT_BALANCE(debtorCollateral);
        }

        // 8) Update state - reduce debtor's collateral and debt
        s_USERS_COLLATERAL_BALANCE[_debtor][_tokenAddress] = debtorCollateral - totalSeize;
        s_USER_MINTED_DSC[_debtor] -= _dscToBurn;
        s_TOKEN_TO_MINTED_DSC[_debtor][_tokenAddress] -= _dscToBurn;

        // 9) Burn DSC from liquidator and transfer collateral to them
        i_DSC.burn(msg.sender, _dscToBurn);
        bool success = IERC20(_tokenAddress).transfer(msg.sender, totalSeize);
        if (!success) revert DSCEngine__TRANSACTION_FAILED();

        emit liqudated(_debtor, totalSeize);

        // 10) Ensure liquidator remains healthy after receiving collateral
        uint256 liquidatorHealthStatus = getHealthStatusForLiquidation(_tokenAddress, msg.sender);
        if (liquidatorHealthStatus < s_MIN_THRESHOLD) {
            revert DSCEngine__HEALTH_AT_RISK();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints DSC against a specific collateral type
     * @param _tokenCollateral The collateral token this DSC will be allocated to
     * @param _amount Amount of DSC to mint
     * @dev Performs forward-looking health check - validates health AFTER minting
     * @dev Also checks protocol-level health to prevent insolvency
     */
    function mintDSC(address _tokenCollateral, uint256 _amount) public noneZero(_amount) {
        (uint256 info,) = getHealth(_tokenCollateral, msg.sender, _amount);

        // Check if protocol will remain solvent after minting
        _checkProtocolHealth(_tokenCollateral, 0, _amount);

        if (info > s_MAX_THRESHOLD) {
            s_USER_MINTED_DSC[msg.sender] += _amount;
            s_TOKEN_TO_MINTED_DSC[msg.sender][_tokenCollateral] += _amount;
            emit mintedDSC(msg.sender, _amount);
            i_DSC.mint(msg.sender, _amount);
        } else if (info < s_MAX_THRESHOLD) {
            revert DSCEngine__HEALTH_AT_RISK();
        }
    }

    /**
     * @notice Deposits collateral into the protocol
     * @param _tokenAddress The collateral token to deposit (WETH or WBTC)
     * @param _amount Amount of collateral to deposit
     * @dev Transfers tokens from user to contract via transferFrom
     */
    function depositCollateral(address _tokenAddress, uint256 _amount)
        public
        onlyAllowedAddress(_tokenAddress)
        noneZero(_amount)
    {
        s_USERS_COLLATERAL_BALANCE[msg.sender][_tokenAddress] += _amount;

        // Track unique users for invariant testing
        if (!s_ALREADY_FUNDED[msg.sender]) {
            s_USERS.push(msg.sender);
            s_ALREADY_FUNDED[msg.sender] = true;
        }

        emit CollateralDeposited(msg.sender, _tokenAddress, _amount);

        bool success = IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert DSCEngine__TRANSACTION_FAILED();
        }
    }

    /**
     * @notice Withdraws collateral from the protocol
     * @param _tokenAddress The collateral token to withdraw
     * @param _amount Amount of collateral to withdraw
     * @dev Performs both current and forward-looking health checks
     * @dev Also validates protocol health after withdrawal
     */
    function redeemCollateral(address _tokenAddress, uint256 _amount)
        public
        onlyAllowedAddress(_tokenAddress)
        noneZero(_amount)
    {
        uint256 balance = getUserCollateralBalance(msg.sender, _tokenAddress);
        if (_amount > balance) {
            revert DSCEngine__INSUFFICIENT_BALANCE(_amount);
        }

        // Check if withdrawal will break protocol health
        _checkProtocolHealth(_tokenAddress, _amount, 0);

        (uint256 totalDSCMinted, uint256 totalCollateralValue) = getUserAccountInfo(_tokenAddress, msg.sender);

        if (totalDSCMinted > 0) {
            // Check current health
            uint256 currentHealth = (totalCollateralValue * s_PRECISION) / totalDSCMinted;
            if (currentHealth < s_MAX_THRESHOLD) {
                revert DSCEngine__HEALTH_AT_RISK();
            }

            // Check health after withdrawal (forward-looking)
            uint256 valueToRedeem = getCollateralValue(getPriceFeed(_tokenAddress), _amount);
            uint256 collateralAfterRedeem = totalCollateralValue - valueToRedeem;
            uint256 healthAfterRedeem = (collateralAfterRedeem * s_PRECISION) / totalDSCMinted;
            if (healthAfterRedeem < s_MAX_THRESHOLD) {
                revert DSCEngine__HEALTH_AT_RISK();
            }
        }

        s_USERS_COLLATERAL_BALANCE[msg.sender][_tokenAddress] -= _amount;
        emit CollateralWithdrawn(msg.sender, _tokenAddress, _amount);

        bool success = IERC20(_tokenAddress).transfer(msg.sender, _amount);
        if (!success) {
            revert DSCEngine__TRANSACTION_FAILED();
        }
    }

    /**
     * @notice Burns DSC to reduce debt
     * @param _amount Amount of DSC to burn
     * @param _token The collateral token this DSC is allocated to
     * @dev DSC must be burned from the specific collateral it was minted against
     */
    function burnDSC(uint256 _amount, address _token) public noneZero(_amount) {
        uint256 dscBalance = getTokenToMintedDSC(msg.sender, _token);
        if (_amount > dscBalance) {
            revert DSCEngine__INSUFFICIENT_BALANCE(_amount);
        }

        s_USER_MINTED_DSC[msg.sender] -= _amount;
        s_TOKEN_TO_MINTED_DSC[msg.sender][_token] -= _amount;
        emit DSCBurned(msg.sender, _amount);

        i_DSC.burn(msg.sender, _amount);
    }

    /**
     * @notice Calculates user's health factor for a potential mint
     * @param _tokenCollateral The collateral token to check against
     * @param _user The user address
     * @param _amount Additional DSC amount to include in health calculation
     * @return info The health factor (collateralValue * 1e18 / totalDebt)
     * @return status Human-readable status: "Good!!!", "Warning!!!", or "Risk!!!"
     * @dev Health >= 150% = Good, 120-150% = Warning, <120% = Risk
     */
    function getHealth(address _tokenCollateral, address _user, uint256 _amount)
        public
        view
        returns (uint256 info, string memory status)
    {
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = getUserAccountInfo(_tokenCollateral, _user);
        if (totalCollateralValue == 0) {
            revert DSCEngine__NO_COLLATERAL_DEPOSITED();
        }

        uint256 debt = _amount + totalDSCMinted;
        uint256 userInfo = (totalCollateralValue * s_PRECISION) / debt;

        if (userInfo >= s_MAX_THRESHOLD) {
            info = userInfo;
            status = "Good!!!";
        } else if (userInfo < s_MAX_THRESHOLD && userInfo >= s_MIN_THRESHOLD) {
            info = userInfo;
            status = "Warning!!!";
        } else if (userInfo < s_MAX_THRESHOLD) {
            info = userInfo;
            status = "Risk!!!";
        }
    }

    /**
     * @notice Gets current health status for liquidation eligibility check
     * @param _tokenCollateral The collateral token to check
     * @param _user The user address
     * @return info The current health factor
     * @dev Reverts if user has no debt (nothing to liquidate)
     */
    function getHealthStatusForLiquidation(address _tokenCollateral, address _user) public view returns (uint256 info) {
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = getUserAccountInfo(_tokenCollateral, _user);
        if (totalDSCMinted == 0) revert DSCEngine__NOT_ENOUGH_DEBT_TO_BURN();
        uint256 userInfo = (totalCollateralValue * s_PRECISION) / totalDSCMinted;
        info = userInfo;
    }

    /**
     * @notice Gets user's total minted DSC and collateral value for a specific collateral type
     * @param _tokenCollateral The collateral token to check
     * @param _user The user address
     * @return totalDSCMinted Total DSC minted against this specific collateral
     * @return totalCollateralValue USD value of deposited collateral (scaled to 1e18)
     */
    function getUserAccountInfo(address _tokenCollateral, address _user)
        public
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        uint256 amount = getUserCollateralBalance(_user, _tokenCollateral);
        address priceFeed = getPriceFeed(_tokenCollateral);

        totalDSCMinted = getTokenToMintedDSC(_user, _tokenCollateral);
        totalCollateralValue = getCollateralValue(priceFeed, amount);
    }

    /**
     * @notice Calculates USD value of collateral amount
     * @param _priceFeedAddress Chainlink price feed address
     * @param _amount Amount of collateral tokens
     * @return USD value scaled to 1e18
     * @dev Uses OracleLib for staleness checks
     */
    function getCollateralValue(address _priceFeedAddress, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);
        (, int256 answer,,,) = priceFeed.roundDataStaleCheck();
        return ((uint256(answer) * 1e10) * _amount) / s_PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates protocol-level health before allowing transactions
     * @param _tokenAddress The collateral token involved in transaction
     * @param _tokenAmount Amount of collateral being withdrawn (0 if minting)
     * @param _DSCAmount Amount of DSC being minted (0 if withdrawing)
     * @dev Ensures total collateral value >= total DSC supply after transaction
     * @dev This prevents protocol insolvency from cross-collateral manipulation
     */
    function _checkProtocolHealth(address _tokenAddress, uint256 _tokenAmount, uint256 _DSCAmount) internal view {
        address wethTokenAddress = getTokenAddress(0);
        address wbtcTokenAddress = getTokenAddress(1);
        address wethPriceFeedAddress = getPriceFeed(wethTokenAddress);
        address wbthPriceFeedAddress = getPriceFeed(wbtcTokenAddress);

        uint256 totalWethHeld = IERC20(wethTokenAddress).balanceOf(address(this));
        uint256 totalWbtcHeld = IERC20(wbtcTokenAddress).balanceOf(address(this));
        uint256 valueOfTotalWeth = getCollateralValue(wethPriceFeedAddress, totalWethHeld);
        uint256 valueOfTotalWbtc = getCollateralValue(wbthPriceFeedAddress, totalWbtcHeld);
        uint256 accumulatedHoldings = valueOfTotalWeth + valueOfTotalWbtc;
        uint256 totalDscSupply = i_DSC.totalSupply();

        // Simulating withdrawal scenario
        if (_DSCAmount == 0) {
            if (_tokenAddress == wethTokenAddress) {
                uint256 valueOfWethToRedeem = getCollateralValue(wethPriceFeedAddress, _tokenAmount);
                uint256 totalWethAfterTx = valueOfTotalWeth - valueOfWethToRedeem;
                uint256 accumulatedHoldingsAfterTx1 = totalWethAfterTx + valueOfTotalWbtc;
                if (accumulatedHoldingsAfterTx1 < totalDscSupply) {
                    revert DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
                }
            }

            if (_tokenAddress == wbtcTokenAddress) {
                uint256 valueOfWbtcToRedeem = getCollateralValue(wbthPriceFeedAddress, _tokenAmount);
                uint256 totalWbtcAfterTx = valueOfTotalWbtc - valueOfWbtcToRedeem;
                uint256 accumulatedHoldingsAfterTx2 = totalWbtcAfterTx + valueOfTotalWeth;
                if (accumulatedHoldingsAfterTx2 < totalDscSupply) {
                    revert DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
                }
            }
        }
        // Simulating minting scenario
        else if (_DSCAmount > 0) {
            uint256 totalDSCAfterTX = totalDscSupply + _DSCAmount;
            if (totalDSCAfterTX > accumulatedHoldings) {
                revert DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
            }
        }
    }

    function _noneZero(uint256 _amount) internal pure {
        if (_amount <= 0) revert DSCEngine__INPUT_AN_AMOUNT();
    }

    function _onlyAllowedAddress(address _tokenAddress) internal view {
        if (!isAllowed[_tokenAddress]) {
            revert DSCEngine__NOT_ALLOWED_TOKEN();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getPriceFeed(address _token) public view returns (address) {
        return s_TOKEN_AND_PRICE_FEED[_token];
    }

    function getTokenAddress(uint256 _index) public view returns (address) {
        return s_TOKEN_ADDRESSES[_index];
    }

    function getUsers(uint256 _index) public view returns (address) {
        return s_USERS[_index];
    }

    function getUsersCount() public view returns (uint256) {
        return s_USERS.length;
    }

    function getUserCollateralBalance(address _user, address _tokenAddress) public view returns (uint256) {
        return s_USERS_COLLATERAL_BALANCE[_user][_tokenAddress];
    }

    function getUserMintedDscBalance(address _user) public view returns (uint256) {
        return s_USER_MINTED_DSC[_user];
    }

    function getTokenToMintedDSC(address _user, address _token) public view returns (uint256) {
        return s_TOKEN_TO_MINTED_DSC[_user][_token];
    }

    function getDSCAddress() public view returns (address) {
        return address(i_DSC);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {DefiStableCoin} from "./DEFI-STABLECOIN.sol";
import {engineLibrary} from "./DSCLIB.sol";

/**
 * @title DSCEngine
 * @author Charles Onyii
 * @notice Central protocol contract for minting the Defi Stablecoin (DSC) against allowed collateral.
 * @dev This protocol implements a novel approach where DSC debt is tracked *per collateral token* for each user,
 * preventing protocol insolvency through granular health checks at both user and system levels.
 *
 * Key Features:
 * - Collateral-Specific Debt: Debt is mapped to the specific collateral used, avoiding cross-collateral risk.
<<<<<<< HEAD
 * - Dual Health Checks: Every risky transaction (mint/withdraw) checks both the user's position health (>= 150%) and the protocol's global solvency (>= 125%).
 * - Liquidation: Positions below 120% collateralization are eligible for liquidation, with a 120-150% grace zone preventing instant liquidation.
 */
contract DSCEngine {
    /*//////////////////////////////////////////////////////////////
    //                         ERRORS
=======
 * - Dual Health Checks: Every risky transaction (mint/withdraw) checks both the user's position health (>150%) and the protocol's global solvency.
 * - Liquidation: Positions below 150% collateralization are eligible for liquidation, with a 120-150% grace zone preventing instant liquidation.
 */
contract DSCEngine {
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
    //                          ERRORS
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    //////////////////////////////////////////////////////////////*/

    /// @dev Thrown when the length of collateral tokens and price feed addresses do not match during construction.
    error DSCEngine__TOKEN_ADDRESSES_AND_PRICE_FEED_ADDRESSES_MUST_BE_SAME_LENGTH();
<<<<<<< HEAD
    /// @dev Thrown when a user attempts to use a token not allowed as collateral (i.e., not configured in the constructor).
    error DSCEngine__NOT_ALLOWED_TOKEN();
    /// @dev Thrown when an input amount (collateral or DSC) is zero, preventing meaningless transactions.
    error DSCEngine__INPUT_AN_AMOUNT();
    /// @dev Thrown when a user's balance is insufficient for a transaction (collateral or DSC).
    /// @param requiredBalance The required balance for the transaction.
    error DSCEngine__INSUFFICIENT_BALANCE(uint256 requiredBalance);
    /// @dev Thrown if an external ERC20 token transfer or operation fails.
    error DSCEngine__TRANSACTION_FAILED();
    /// @dev Thrown if a transaction (mint or withdraw collateral) would cause the user's health factor to drop below the minimum safe threshold (150%).
    error DSCEngine__HEALTH_AT_RISK();
    /// @dev Thrown if a user attempts to mint DSC without depositing any collateral first, as debt must be backed by assets.
    error DSCEngine__NO_COLLATERAL_DEPOSITED();
    /// @dev Thrown if a liquidation is attempted on a user whose health factor is already safe (>= 150% or "Good!!!").
    error DSCEngine__HEALTH_IS_GOOD();
    /// @dev Thrown if a liquidation is attempted on a user whose health factor is in the grace zone (120% <= HF < 150% or "Warning!!!").
    error DSCEngine__HEALTH_AT_GRACE_ZONE();
    /// @dev Thrown during liquidation if the liquidator tries to burn more than 50% of the debtor's debt against the specific collateral.
    error DSCEngine__CANNOT_BURN_MORE_THAN_HALF_OF_DEBT();
    /// @dev Thrown if a transaction would cause the total DSC supply to exceed 80% of the protocol's total collateral value (i.e., global collateralization drops below 125%).
    error DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
    /// @dev Thrown when attempting to get a health status or burn DSC when the user has zero debt associated with the given collateral.
    error DSCEngine__NOT_ENOUGH_DEBT_TO_BURN();

    /*//////////////////////////////////////////////////////////////
    //                       STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Divisor for calculating the maximum allowed debt burn during liquidation (2 for 50%).
    uint8 private constant s_HALF_OF_DEBTORS_BALANCE = 2;
    /// @notice Percentage value used for the liquidation bonus (10%).
    uint8 private constant s_PERCENTAGE = 10;
    /// @notice Scale factor for percentage calculations (100).
    uint8 private constant s_PERCENTAGE_SCALE = 100;

    /// @notice Precision scaler used for fixed-point arithmetic calculations (1e18).
    uint128 private constant s_PRECISION = 1e18;
    /// @notice Scaler used to normalize Chainlink price feed results (typically 1e10 for 8-decimal feeds).
    uint128 private constant s_PRICE_FEED_SCALE = 1e10;

    /// @notice Array of allowed collateral token addresses (e.g., WETH, WBTC).
    address[] private s_TOKEN_ADDRESSES;

    /// @notice Tracks which token addresses are allowed to be used as collateral.
    mapping(address tokenAddreses => bool) private isAllowed;

    /// @notice Maps allowed collateral token addresses to their Chainlink price feed addresses.
    mapping(address tokenAddress => address priceFeed) private s_TOKEN_AND_PRICE_FEED;

    /// @notice Maps user address and collateral token to DSC debt minted specifically against that collateral.
    /// @dev This is the key mechanism for collateral-specific debt tracking, ensuring debt is isolated by collateral type.
    mapping(address user => mapping(address token => uint256 mintedDSC)) private s_TOKEN_TO_MINTED_DSC;

    /// @notice Maps user address and collateral token to the amount of deposited collateral held by the engine.
    mapping(address user => mapping(address tokenAddress => uint256 collateral)) private s_USERS_COLLATERAL_BALANCE;

    /// @notice The immutable address of the DefiStableCoin contract instance.
    DefiStableCoin private immutable i_DSC;

    /*//////////////////////////////////////////////////////////////
    //                         MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if the provided token address is an allowed collateral type configured in the engine.
=======
    /// @dev Thrown when a user attempts to use a token not allowed as collateral.
    error DSCEngine__NOT_ALLOWED_TOKEN();
    /// @dev Thrown when an input amount (collateral or DSC) is zero.
    error DSCEngine__INPUT_AN_AMOUNT();
    /// @dev Thrown when a user's balance is insufficient for a transaction (collateral or DSC).
    error DSCEngine__INSUFFICIENT_BALANCE(uint256 requiredBalance);
    /// @dev Thrown if an external token transfer or operation fails.
    error DSCEngine__TRANSACTION_FAILED();
    /// @dev Thrown if a transaction would cause the user's health factor to drop below the minimum threshold (150% for risky actions, 120% for liquidation).
    error DSCEngine__HEALTH_AT_RISK();
    /// @dev Thrown if a user attempts to mint DSC without depositing any collateral first.
    error DSCEngine__NO_COLLATERAL_DEPOSITED();
    /// @dev Thrown if a liquidation is attempted on a user whose health factor is already safe (> 150%).
    error DSCEngine__HEALTH_IS_GOOD();
    /// @dev Thrown if a liquidation is attempted on a user whose health factor is in the grace zone (120% <= HF < 150%).
    error DSCEngine__HEALTH_AT_GRACE_ZONE();
    /// @dev Thrown during liquidation if the liquidator tries to burn more than 50% of the debtor's debt.
    error DSCEngine__CANNOT_BURN_MORE_THAN_HALF_OF_DEBT();
    /// @dev Thrown if a transaction would cause the total DSC supply to exceed 80% of the protocol's total collateral value.
    error DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
    /// @dev Thrown when attempting to get a health status for a user with zero debt.
    error DSCEngine__NOT_ENOUGH_DEBT_TO_BURN();

    /*//////////////////////////////////////////////////////////////
    //                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of allowed collateral token addresses (e.g., WETH, WBTC).
    address[] private s_TOKEN_ADDRESSES;

    /// @notice Array of addresses that have ever deposited collateral (used for protocol health checks/invariants).
    address[] private s_USERS;

    /// @notice Maximum health threshold (150% scaled to 1e18) - below this triggers liquidation eligibility.
    uint256 private constant s_MAX_THRESHOLD = 1500000000000000000; // 1.5e18

    /// @notice Minimum health threshold (120% scaled to 1e18) - the lower bound of the grace zone, and minimum requirement for a healthy user.
    uint256 private constant s_MIN_THRESHOLD = 1200000000000000000; // 1.2e18

    /// @notice Precision scaler used for fixed-point arithmetic (1e18).
    uint256 private constant s_PRECISION = 1e18;

    /// @notice Divisor for calculating the maximum allowed debt burn during liquidation (2 for 50%).
    uint256 private constant s_HALF_OF_DEBTORS_BALANCE = 2;

    /// @notice Tracks which tokens are allowed as collateral.
    mapping(address tokenAddreses => bool) private isAllowed;

    /// @notice Total DSC debt minted by each user across all collateral types.
    mapping(address user => uint256 mintedDSC) private s_USER_MINTED_DSC;

    /// @notice Maps collateral token addresses to their Chainlink price feed addresses.
    mapping(address tokenAddress => address priceFeed) private s_TOKEN_AND_PRICE_FEED;

    /// @notice Tracks if a user has already deposited collateral to avoid duplicate entries in s_USERS.
    mapping(address users => bool) private s_ALREADY_FUNDED;

    /// @notice Maps user address and collateral token to DSC debt minted specifically against that collateral.
    /// @dev This is the key mechanism for collateral-specific debt tracking.
    mapping(address user => mapping(address token => uint256 mintedDSC)) private s_TOKEN_TO_MINTED_DSC;

    /// @notice Maps user address and collateral token to the deposited collateral amount.
    mapping(address user => mapping(address tokenAddress => uint256 collateral)) private s_USERS_COLLATERAL_BALANCE;

    /// @notice The DSC stablecoin contract instance.
    DefiStableCoin private immutable i_DSC;

    /*//////////////////////////////////////////////////////////////
    //                          MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if the provided token address is an allowed collateral type.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @param _tokenAddress The token address to validate.
     */
    modifier onlyAllowedAddress(address _tokenAddress) {
        _onlyAllowedAddress(_tokenAddress);
        _;
    }

    /**
<<<<<<< HEAD
     * @notice Checks that the provided amount is strictly greater than zero.
=======
     * @notice Checks that the provided amount is greater than zero.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @param _amount The amount to validate.
     */
    modifier noneZero(uint256 _amount) {
        _noneZero(_amount);
        _;
    }

    /*//////////////////////////////////////////////////////////////
<<<<<<< HEAD
    //                          EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits collateral into the protocol.
=======
    //                           EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits collateral.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    /// @param user The address of the user depositing collateral.
    /// @param token The collateral token address.
    /// @param amount The amount of collateral deposited.
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
<<<<<<< HEAD

    /// @notice Emitted when a user successfully withdraws collateral from the protocol.
=======
    
    /// @notice Emitted when a user withdraws collateral.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    /// @param user The address of the user withdrawing collateral.
    /// @param token The collateral token address.
    /// @param amount The amount of collateral withdrawn.
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
<<<<<<< HEAD

=======
    
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    /// @notice Emitted when a user successfully mints DSC.
    /// @param user The address of the user minting DSC.
    /// @param amount The amount of DSC minted.
    event mintedDSC(address indexed user, uint256 amount);
<<<<<<< HEAD

=======
    
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    /// @notice Emitted when a user burns DSC to repay debt.
    /// @param user The address of the user burning DSC.
    /// @param amount The amount of DSC burned.
    event DSCBurned(address indexed user, uint256 amount);
<<<<<<< HEAD

    /// @notice Emitted after a successful liquidation event.
    /// @param user The address of the debtor who was liquidated.
    /// @param amount The total amount of collateral seized by the liquidator (including the 10% bonus).
=======
    
    /// @notice Emitted after a successful liquidation.
    /// @param user The address of the debtor who was liquidated.
    /// @param amount The total amount of collateral seized (including the 10% bonus).
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    event liqudated(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
    //                         CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the DSC Engine with allowed collateral tokens and their respective Chainlink price feeds.
     * @param _tokenAddresses Array of allowed collateral token addresses (e.g., WETH, WBTC).
     * @param _priceFeedAddresses Array of Chainlink price feed addresses corresponding to tokens.
     * @param _dscAddress Address of the DefiStableCoin contract.
<<<<<<< HEAD
     * @dev Token addresses and price feed addresses must be in the same order and of the same length.
=======
     * @dev Token addresses and price feed addresses must be in the same order and length.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    constructor(address[2] memory _tokenAddresses, address[2] memory _priceFeedAddresses, address _dscAddress) {
        if (_priceFeedAddresses.length != _tokenAddresses.length) {
            revert DSCEngine__TOKEN_ADDRESSES_AND_PRICE_FEED_ADDRESSES_MUST_BE_SAME_LENGTH();
        }
        // Using length of the input array for iteration
        uint256 len = _tokenAddresses.length;
        for (uint256 i = 0; i < len; i++) {
            s_TOKEN_AND_PRICE_FEED[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_TOKEN_ADDRESSES.push(_tokenAddresses[i]);
            isAllowed[_tokenAddresses[i]] = true;
        }
        i_DSC = DefiStableCoin(_dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
    //                       EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits collateral and mints DSC in a single, atomic transaction.
<<<<<<< HEAD
     * @param _tokenAddress The collateral token to deposit (e.g., WETH or WBTC).
=======
     * @param _tokenAddress The collateral token to deposit (WETH or WBTC).
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @param _collateralAmount Amount of collateral to deposit.
     * @param _dscAmount Amount of DSC to mint against the deposited collateral.
     * @dev This transaction requires prior approval of collateral transfer via ERC20 `approve`.
     * @dev Performs dual health checks: user health check (>= 150%) and protocol health check (global collateralization >= 125%).
     */
    function depositCollateralForDSC(address _tokenAddress, uint256 _collateralAmount, uint256 _dscAmount) external {
        depositCollateral(_tokenAddress, _collateralAmount);
        mintDSC(_tokenAddress, _dscAmount);
    }

    /**
     * @notice Burns DSC to repay debt and withdraws collateral in a single, atomic transaction.
     * @param _tokenAddress The collateral token to redeem.
     * @param _collateralAmount Amount of collateral to redeem.
     * @param _dscAmount Amount of DSC to burn.
<<<<<<< HEAD
     * @dev Burning DSC is performed first to immediately improve the user's health factor before checking withdrawal eligibility.
=======
     * @dev Burning DSC is performed first to immediately improve the user's health factor before attempting withdrawal.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @dev Withdrawal of collateral requires the position to be at a healthy level (>= 150%) before and after the transaction.
     */
    function redeemCollateralWithDSC(address _tokenAddress, uint256 _collateralAmount, uint256 _dscAmount) external {
        burnDSC(_dscAmount, _tokenAddress);
        redeemCollateral(_tokenAddress, _collateralAmount);
    }

    /**
     * @notice Liquidates an undercollateralized position by burning DSC debt for the debtor's collateral.
<<<<<<< HEAD
     * @param _tokenAddress The collateral token to seize (must match the collateral the debt was taken against).
     * @param _debtor The address of the user being liquidated.
     * @param _dscToBurn Amount of DSC the liquidator burns (max 50% of debtor's debt against the collateral).
     * @dev Liquidation criteria: Debtor's health must be < 120% ("Risk!!!"). Cannot liquidate if health is between 120% and 150% (grace zone).
=======
     * @param _tokenAddress The collateral token to seize.
     * @param _debtor The address of the user being liquidated.
     * @param _dscToBurn Amount of DSC the liquidator burns (max 50% of debtor's debt against the collateral).
     * @dev Liquidation criteria: Debtor's health must be < 150%. Cannot liquidate if health is between 120% and 150% (grace zone).
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @dev Liquidator receives a 10% bonus on the value of the seized collateral.
     * @dev The liquidator's own health factor is checked *after* receiving the bonus collateral to ensure they are not abusing the system.
     */
    function liquidate(address _tokenAddress, address _debtor, uint256 _dscToBurn)
        external
        onlyAllowedAddress(_tokenAddress)
        noneZero(_dscToBurn)
    {
        // 1) Health checks - ensure debtor is liquidatable
        (, string memory debtorsStatus) = getUsersHealthStatus(_tokenAddress, _debtor);
        _revertAfterUserHealthCheck(0, debtorsStatus);

        // 2) Compute allowed maximum (50% of debt to prevent full liquidation)
        uint256 maxAllowedToBurn = getTokenToMintedDSC(_debtor, _tokenAddress) / s_HALF_OF_DEBTORS_BALANCE;
        if (_dscToBurn > maxAllowedToBurn) {
            revert DSCEngine__CANNOT_BURN_MORE_THAN_HALF_OF_DEBT();
        }

        // 3) Check liquidator has sufficient DSC balance
        uint256 liquidatorDscBalance = i_DSC.balanceOf(msg.sender);
        if (liquidatorDscBalance < _dscToBurn) {
            revert DSCEngine__INSUFFICIENT_BALANCE(liquidatorDscBalance);
        }

        // 4) Get amount to seize, including the 10% bonus
        uint256 totalToSeize = _getAmountToSeize(_tokenAddress, _dscToBurn);

<<<<<<< HEAD
        // 5) Ensure debtor has enough collateral
=======
        uint256 priceScaled = uint256(answer) * 1e10; // Scale to 1e18

        // 5) Calculate collateral to seize based on DSC amount (CollateralValue = DSC * Price)
        // collateralToSeize = (DSC_to_Burn * 1e18) / Price_Scaled
        uint256 collateralToSeize = (_dscToBurn * s_PRECISION) / priceScaled;

        // 6) Add 10% liquidation bonus (CollateralToSeize * 1.1)
        uint256 bonus;
        unchecked {
            // Unchecked here is safe as the values are small and are multiplied by 10/100
            bonus = (collateralToSeize * 10) / 100; 
        }
        uint256 totalSeize = collateralToSeize + bonus;

        // 7) Ensure debtor has enough collateral
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        uint256 debtorCollateral = s_USERS_COLLATERAL_BALANCE[_debtor][_tokenAddress];
        if (debtorCollateral < totalToSeize) {
            revert DSCEngine__INSUFFICIENT_BALANCE(debtorCollateral);
        }

        // 6) Update state - reduce debtor's collateral and debt
        s_USERS_COLLATERAL_BALANCE[_debtor][_tokenAddress] -= totalToSeize;
        s_TOKEN_TO_MINTED_DSC[_debtor][_tokenAddress] -= _dscToBurn;

        // 7) Burn DSC from liquidator and transfer collateral to them
        // DSC is burned from the liquidator's balance
        i_DSC.burn(msg.sender, _dscToBurn);
        // Collateral is transferred from this contract to the liquidator
        bool success = IERC20(_tokenAddress).transfer(msg.sender, totalToSeize);
        if (!success) revert DSCEngine__TRANSACTION_FAILED();

        emit liqudated(_debtor, totalToSeize);

<<<<<<< HEAD
        // 8) Ensure liquidator remains healthy after receiving collateral
        // This prevents the liquidator from using the liquidation bonus as a debt tool if they themselves have debt.
        (uint256 info, string memory status) = getUsersHealthStatus(_tokenAddress, msg.sender);
        _revertAfterUserHealthCheck(info, status);
=======
        // 10) Ensure liquidator remains healthy after receiving collateral
        (, string memory status) = getUsersHealthStatus(_tokenAddress, msg.sender);
        bytes32 liqEncodedStatus = keccak256(abi.encodePacked(status));
        if (liqEncodedStatus != _statusString("Good!!!")) {
            revert DSCEngine__HEALTH_AT_RISK();
        }
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    }

    /*//////////////////////////////////////////////////////////////
    //                        PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints DSC and allocates the debt specifically against the provided collateral token.
     * @param _tokenCollateral The collateral token this DSC debt will be mapped to (e.g., WETH).
     * @param _amount Amount of DSC to mint.
<<<<<<< HEAD
     * @dev Performs a **forward-looking** user health check: validates the user's health factor *after* the minting.
     * @dev Reverts if the user's post-mint health is < 150% (minimum safety threshold).
     * @dev Also checks **protocol-level** health to prevent total DSC supply from exceeding the 80% collateral cap (global 125% collateralization).
=======
     * @dev Performs a **forward-looking** health check: validates the user's health factor *after* the minting.
     * @dev Reverts if the user's post-mint health is < 150% (s_MAX_THRESHOLD).
     * @dev Also checks **protocol-level** health to prevent total DSC supply from exceeding the 80% collateral cap.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    function mintDSC(address _tokenCollateral, uint256 _amount) public noneZero(_amount) {
        // Calculate user health factor if this new debt is added
        (uint256 userInfo,) = _getHealth(_tokenCollateral, msg.sender, _amount);

<<<<<<< HEAD
        // Revert if the user's health factor after minting is below the 150% threshold
        _revertAfterUserHealthCheck(userInfo, "");

        s_TOKEN_TO_MINTED_DSC[msg.sender][_tokenCollateral] += _amount;
        emit mintedDSC(msg.sender, _amount);

        // The DefiStableCoin contract mints the token to the user
=======
        // Revert if the user's health factor after minting is below the minimum threshold
        _revertAfterUserHealthCheck(userInfo, "");

        s_USER_MINTED_DSC[msg.sender] += _amount;
        s_TOKEN_TO_MINTED_DSC[msg.sender][_tokenCollateral] += _amount;
        emit mintedDSC(msg.sender, _amount);
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        i_DSC.mint(msg.sender, _amount);

        // Check if protocol will remain solvent after minting (Total Collateral Value >= 125% * Total DSC Supply)
        _checkProtocolHealth();
    }

    /**
<<<<<<< HEAD
     * @notice Deposits an allowed collateral token into the protocol, increasing the user's collateral balance.
     * @param _tokenAddress The collateral token to deposit.
     * @param _amount Amount of collateral to deposit.
     * @dev Requires the user to approve this contract to transfer tokens beforehand (ERC20 `transferFrom`).
=======
     * @notice Deposits an allowed collateral token into the protocol.
     * @param _tokenAddress The collateral token to deposit.
     * @param _amount Amount of collateral to deposit.
     * @dev Requires the user to approve this contract to transfer tokens beforehand (ERC20 `transferFrom`).
     * @dev Tracks unique users for protocol invariant checks.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    function depositCollateral(address _tokenAddress, uint256 _amount)
        public
        onlyAllowedAddress(_tokenAddress)
        noneZero(_amount)
    {
        s_USERS_COLLATERAL_BALANCE[msg.sender][_tokenAddress] += _amount;
<<<<<<< HEAD
=======

        // Track unique users for invariant testing and protocol-wide health checks
        if (!s_ALREADY_FUNDED[msg.sender]) {
            s_USERS.push(msg.sender);
            s_ALREADY_FUNDED[msg.sender] = true;
        }

>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        emit CollateralDeposited(msg.sender, _tokenAddress, _amount);

        bool success = IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert DSCEngine__TRANSACTION_FAILED();
        }
    }

    /**
     * @notice Withdraws a portion of the user's deposited collateral.
     * @param _tokenAddress The collateral token to withdraw.
     * @param _amount Amount of collateral to withdraw.
     * @dev Requires the user's position to be at least 150% collateralized *before* and *after* the withdrawal.
     * @dev Also performs a protocol health check to ensure the withdrawal does not violate the global 125% collateralization invariant.
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

        (uint256 totalDSCMinted, uint256 totalCollateralValue) = getUserAccountInfo(_tokenAddress, msg.sender);

        if (totalDSCMinted > 0) {
            // Check current health (must be >= 150% to withdraw collateral)
            uint256 userThreshold = (totalCollateralValue * s_PRECISION) / totalDSCMinted;
            _revertAfterUserHealthCheck(userThreshold, "");

            // Check health after withdrawal (forward-looking check)
<<<<<<< HEAD
            (uint256 valueToRedeem,) = engineLibrary._getCollateralValue(getPriceFeed(_tokenAddress), _amount);
=======
            uint256 valueToRedeem = getCollateralValue(getPriceFeed(_tokenAddress), _amount);
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
            uint256 collateralAfterRedeem = totalCollateralValue - valueToRedeem;

            // Health Factor = (Collateral Value After Redeem * 1e18) / Total DSC Debt
            uint256 healthAfterRedeem = (collateralAfterRedeem * s_PRECISION) / totalDSCMinted;
            _revertAfterUserHealthCheck(healthAfterRedeem, "");
        }

        s_USERS_COLLATERAL_BALANCE[msg.sender][_tokenAddress] -= _amount;
        emit CollateralWithdrawn(msg.sender, _tokenAddress, _amount);

        bool success = IERC20(_tokenAddress).transfer(msg.sender, _amount);
        if (!success) {
            revert DSCEngine__TRANSACTION_FAILED();
        }

        // Check if withdrawal will break protocol health (Total Collateral Value >= 125% * Total DSC Supply)
        _checkProtocolHealth();
    }

    /**
     * @notice Burns DSC to reduce debt against a specific collateral token.
     * @param _amount Amount of DSC to burn.
<<<<<<< HEAD
     * @param _token The collateral token this DSC debt is allocated to (e.g., WETH if the debt was minted against WETH).
=======
     * @param _token The collateral token this DSC debt is allocated to.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @dev The debt must be repaid against the specific collateral it was minted for (collateral-specific debt repayment).
     */
    function burnDSC(uint256 _amount, address _token) public noneZero(_amount) {
        uint256 dscBalance = getTokenToMintedDSC(msg.sender, _token);
        if (_amount > dscBalance) {
            revert DSCEngine__INSUFFICIENT_BALANCE(_amount);
        }

        s_TOKEN_TO_MINTED_DSC[msg.sender][_token] -= _amount;
        emit DSCBurned(msg.sender, _amount);

        // The DefiStableCoin contract burns the tokens from the user
        i_DSC.burn(msg.sender, _amount);
    }

    /**
     * @notice Gets the current health status and factor for a user's position against a specific collateral.
     * @param _tokenCollateral The collateral token to check.
     * @param _user The user address.
     * @return info The user's current health factor (scaled to 1e18).
     * @return status Human-readable status string ("Good!!!", "Warning!!!", or "Risk!!!").
<<<<<<< HEAD
     * @dev Reverts if the user has no debt (health check is not applicable as the denominator is zero).
=======
     * @dev Reverts if the user has no debt (health check is not applicable).
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    function getUsersHealthStatus(address _tokenCollateral, address _user)
        public
        view
        returns (uint256 info, string memory status)
    {
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = getUserAccountInfo(_tokenCollateral, _user);
        if (totalDSCMinted == 0) revert DSCEngine__NOT_ENOUGH_DEBT_TO_BURN();

        // Health Factor = (Total Collateral Value * 1e18) / Total DSC Debt
        uint256 userInfo = (totalCollateralValue * s_PRECISION) / totalDSCMinted;

<<<<<<< HEAD
        (, string memory healthStatus) = engineLibrary._getHealthStatus(userInfo);
=======
        (, string memory healthStatus) = _getHealthStatus(userInfo);
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        return (userInfo, healthStatus);
    }

    /**
     * @notice Gets a user's total DSC debt and the USD value of their collateral for a specific collateral type.
     * @param _tokenCollateral The collateral token to check.
     * @param _user The user address.
     * @return totalDSCMinted Total DSC debt minted against this specific collateral.
     * @return totalCollateralValue USD value of deposited collateral (scaled to 1e18).
     */
    function getUserAccountInfo(address _tokenCollateral, address _user)
        public
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        uint256 amount = getUserCollateralBalance(_user, _tokenCollateral);
        address priceFeed = getPriceFeed(_tokenCollateral);
        uint256 tokenMintedDSC = getTokenToMintedDSC(_user, _tokenCollateral);
        (uint256 collateralValue,) = engineLibrary._getCollateralValue(priceFeed, amount);

<<<<<<< HEAD
        totalDSCMinted = tokenMintedDSC;
        totalCollateralValue = collateralValue;
=======
        totalDSCMinted = getTokenToMintedDSC(_user, _tokenCollateral);
        totalCollateralValue = getCollateralValue(priceFeed, amount);
    }

    /**
     * @notice Calculates the USD value of a given amount of collateral.
     * @param _priceFeedAddress Chainlink price feed address for the collateral.
     * @param _amount Amount of collateral tokens.
     * @return USD value scaled to 1e18.
     * @dev Utilizes `OracleLib.roundDataStaleCheck()` for a robust price fetch with staleness checks, ensuring safety.
     */
    function getCollateralValue(address _priceFeedAddress, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);
        // Uses OracleLib's roundDataStaleCheck to ensure fresh price
        (, int256 answer,,,) = priceFeed.roundDataStaleCheck();

        // Value = (Price * Amount) / 1e18 (since price is scaled to 1e10 internally, and Amount is 1e18)
        return ((uint256(answer) * 1e10) * _amount) / s_PRECISION;
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    }

    /*//////////////////////////////////////////////////////////////
    //                       INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
<<<<<<< HEAD
     * @notice Validates protocol-level health by checking the total collateral held against the total DSC supply.
=======
     * @notice Validates protocol-level health.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @dev Enforces the global invariant: Total Collateral Value (USD) >= 125% * Total DSC Supply.
     */
    function _checkProtocolHealth() internal view {
        uint256 totalDscSupply = i_DSC.totalSupply();
<<<<<<< HEAD
        // This function returns the total required collateral value to maintain the 125% collateralization ratio
        uint256 protocolAccumulatedHoldings = _checkDSCData();

        // If total DSC supply is greater than the required collateral value to back it at the safe ratio, revert.
=======
        uint256 protocolAccumulatedHoldings = _checkDSCData();

>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        if (totalDscSupply >= protocolAccumulatedHoldings) {
            revert DSCEngine__PROTOCOLS_HEALTH_AT_RISK();
        }
    }

<<<<<<< HEAD
    /**
     * @notice Reverts the transaction based on the user's health factor. This is a dual-purpose internal check.
     * @param _userInfo The calculated health factor (scaled to 1e18) for risky operations (mint/withdraw). Set to 0 for liquidation checks.
     * @param _status The human-readable status string (e.g., "Risk!!!") used only for the liquidation eligibility check.
     * @dev **For Risky Operations (Mint/Redeem):** If `_userInfo` is non-zero, it checks if health is >= 150% ("Good!!!"). Reverts with `DSCEngine__HEALTH_AT_RISK` if below.
     * @dev **For Liquidation Eligibility:** If `_userInfo` is zero, it uses `_status` to check if the debtor is in the "Risk!!!" zone (< 120%). Reverts if "Good!!!" or "Warning!!!".
=======

    /**
     * @notice Reverts the transaction based on the user's health factor, used for both forward-looking checks and liquidation eligibility.
     * @param _userInfo The calculated health factor (0 if checking status only, e.g., during liquidation start).
     * @param _status The human-readable status string (used for liquidation check).
     * @dev If `_userInfo` is non-zero (risky operation like mint/withdraw), it checks if health is >= 150%.
     * @dev If `_userInfo` is zero (liquidation), it checks if the debtor is in the "Risk!!!" zone (< 120%).
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    function _revertAfterUserHealthCheck(uint256 _userInfo, string memory _status) internal pure {
        // User Health Futuristic Check (Redeem Collateral, Mint)
        // If _userInfo is not 0, it means we are checking the *future* state of health
        if (_userInfo != 0) {
<<<<<<< HEAD
            (bytes32 encodedInfo,) = engineLibrary._getHealthStatus(_userInfo);
            // Must be 'Good!!!' (>= 150%) to proceed with a risky transaction (mint/redeem collateral)
            if (encodedInfo != engineLibrary._statusString("Good!!!")) revert DSCEngine__HEALTH_AT_RISK();
=======
            (bytes32 encodedInfo,) = _getHealthStatus(_userInfo);
            // Must be 'Good!!!' (>= 150%) to proceed with a risky transaction (mint/redeem collateral)
            if (encodedInfo != _statusString("Good!!!")) revert DSCEngine__HEALTH_AT_RISK();
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        }
        // Liquidation Eligibility Check
        // If _userInfo is 0, we are checking the *current* status for liquidation
        else if (_userInfo == 0) {
<<<<<<< HEAD
            bytes32 encodedStatus = engineLibrary._statusString(_status);
            // Cannot liquidate if good (>= 150%)
            if (encodedStatus == engineLibrary._statusString("Good!!!")) revert DSCEngine__HEALTH_IS_GOOD();
            // Cannot liquidate if in grace zone (120% - 150%)
            if (encodedStatus == engineLibrary._statusString("Warning!!!")) revert DSCEngine__HEALTH_AT_GRACE_ZONE();
            // If it's "Risk!!!", liquidation proceeds (implicit fallthrough).
=======
            bytes32 encodedStatus = _statusString(_status);
            // Cannot liquidate if good (>= 150%)
            if (encodedStatus == _statusString("Good!!!")) revert DSCEngine__HEALTH_IS_GOOD();
            // Cannot liquidate if in grace zone (120% - 150%)
            if (encodedStatus == _statusString("Warning!!!")) revert DSCEngine__HEALTH_AT_GRACE_ZONE();
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        }
    }

    /**
     * @notice Calculates the total USD value of all collateral held by the protocol.
     * @dev This function iterates through all allowed collateral tokens to sum up the USD value of protocol holdings.
<<<<<<< HEAD
     * @dev The use of `unchecked` is a gas optimization, assuming the loop index will not overflow a `uint256` before hitting `len`.
     * @return protocolAccumulatedHoldings Total USD value of all collateral (scaled to 1e18).
=======
     * @dev Uses a gas-optimized `unchecked` loop with `uint8` for length caching, leveraging the architectural constraint of max 255 tokens.
     * @return protocolAccumulatedHoldings Total USD value of all collateral.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    function _checkDSCData() internal view returns (uint256 protocolAccumulatedHoldings) {
        // Caching length into uint8 based on domain assumption that collateral list will not exceed 255 tokens
        uint8 len = uint8(s_TOKEN_ADDRESSES.length);
<<<<<<< HEAD

=======
        
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        for (uint256 i = 0; i < len;) {
            address token = getTokenAddress(i);
            address priceFeed = getPriceFeed(token);
            uint256 balanceHeld = IERC20(token).balanceOf(address(this));
<<<<<<< HEAD
            (uint256 balanceCollateralValue,) = engineLibrary._getCollateralValue(priceFeed, balanceHeld);

=======
            uint256 balanceCollateralValue = getCollateralValue(priceFeed, balanceHeld);
            
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
            // Standard addition (checked by default)
            protocolAccumulatedHoldings += balanceCollateralValue;

            // CORRECT UNCHECKED INCREMENT (Gas Optimization)
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Calculates the user's health factor, including a potential additional debt amount.
     * @param _tokenCollateral The collateral token used for calculation.
     * @param _user The user address.
<<<<<<< HEAD
     * @param _amount Additional DSC debt amount to include (used for forward-looking checks in `mintDSC`).
     * @return info The health factor (collateralValue * 1e18 / totalDebt).
     * @return status Encoded status (bytes32) for internal comparison.
=======
     * @param _amount Additional DSC debt amount to include (used for forward-looking checks).
     * @return info The health factor (collateralValue * 1e18 / totalDebt).
     * @return status Encoded status for internal comparison.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     */
    function _getHealth(address _tokenCollateral, address _user, uint256 _amount)
        internal
        view
        returns (uint256 info, bytes32 status)
    {
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = getUserAccountInfo(_tokenCollateral, _user);
        if (totalCollateralValue == 0) {
            revert DSCEngine__NO_COLLATERAL_DEPOSITED();
        }

        uint256 debt = _amount + totalDSCMinted;
        // Health Factor = (Total Collateral Value * 1e18) / Total DSC Debt
        uint256 userInfo = (totalCollateralValue * s_PRECISION) / debt;
<<<<<<< HEAD
        (bytes32 encodedStatus,) = engineLibrary._getHealthStatus(userInfo);
=======
        (bytes32 encodedStatus,) = _getHealthStatus(userInfo);
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
        return (userInfo, encodedStatus);
    }

    /**
<<<<<<< HEAD
     * @notice Calculates the exact amount of collateral to seize for a given amount of DSC debt repaid by a liquidator, including the 10% bonus.
     * @param _tokenAddress The collateral token being seized.
     * @param _dscToBurn The amount of DSC debt the liquidator is paying off (in 1e18).
     * @return totalSeize The total amount of collateral tokens (in their native unit) to seize, including the 10% bonus.
     * @dev Formula for base collateral: `Base Collateral = (DSC_to_Burn * 1e18) / Price_in_USD`.
     */
    function _getAmountToSeize(address _tokenAddress, uint256 _dscToBurn) internal view returns (uint256 totalSeize) {
        address collateralPriceFeed = getPriceFeed(_tokenAddress);
        // Returns the price of the collateral token, scaled to 1e18 (as the second return value)
        (, uint256 answer) = engineLibrary._getCollateralValue(collateralPriceFeed, _dscToBurn);
        if (answer <= 0) revert DSCEngine__TRANSACTION_FAILED();

        // collateralToSeize (token amount) = (_dscToBurn * s_PRECISION) / priceScaled
        // This division result is the base collateral amount in token units (1e18) needed to cover the debt.
        uint256 collateralToSeize = (_dscToBurn * s_PRECISION) / answer;

        uint256 bonus;
        unchecked {
            // Calculate 10% bonus (collateralToSeize * 10 / 100)
            bonus = (collateralToSeize * s_PERCENTAGE) / s_PERCENTAGE_SCALE;
        }
        totalSeize = collateralToSeize + bonus;

        return totalSeize;
    }

    /**
     * @notice Internal validation that an amount is strictly greater than zero.
=======
     * @notice Determines the human-readable and encoded health status based on the health factor.
     * @param _userInfo The health factor (scaled to 1e18).
     * @return encoded Encoded status using keccak256 for gas-efficient comparison.
     * @return status Human-readable status: "Good!!!" (>= 150%), "Warning!!!" (120% to 150%), or "Risk!!!" (< 120%).
     */
    function _getHealthStatus(uint256 _userInfo) internal pure returns (bytes32 encoded, string memory status) {
        if (_userInfo >= s_MAX_THRESHOLD) {
            bytes32 encodedGood = _statusString("Good!!!");
            return (encodedGood, "Good!!!");
        } else if (_userInfo < s_MAX_THRESHOLD && _userInfo >= s_MIN_THRESHOLD) {
            bytes32 encodedWarning = _statusString("Warning!!!");
            return (encodedWarning, "Warning!!!");
        } else {
            // _userInfo < s_MIN_THRESHOLD
            bytes32 encodedRisk = _statusString("Risk!!!");
            return (encodedRisk, "Risk!!!");
        }
    }

    /**
     * @notice Encodes a status string using keccak256 for gas-efficient comparison.
     * @param _status The string to encode.
     * @return bytes32 The encoded status.
     */
    function _statusString(string memory _status) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_status));
    }

    /**
     * @notice Internal validation that an amount is greater than zero.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
     * @param _amount The amount to check.
     */
    function _noneZero(uint256 _amount) internal pure {
        if (_amount <= 0) revert DSCEngine__INPUT_AN_AMOUNT();
    }

    /**
     * @notice Internal validation that a token address is allowed as collateral.
     * @param _tokenAddress The token address to check.
     */
    function _onlyAllowedAddress(address _tokenAddress) internal view {
        if (!isAllowed[_tokenAddress]) {
            revert DSCEngine__NOT_ALLOWED_TOKEN();
        }
    }

    /*//////////////////////////////////////////////////////////////
<<<<<<< HEAD
    //                        VIEW FUNCTIONS
=======
    //                         VIEW FUNCTIONS
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the price feed address for a given collateral token.
    /// @param _token The collateral token address.
    /// @return The Chainlink AggregatorV3Interface address.
    function getPriceFeed(address _token) public view returns (address) {
        return s_TOKEN_AND_PRICE_FEED[_token];
    }

<<<<<<< HEAD
    /// @notice Returns an allowed collateral token address by its index in the array.
    /// @param _index The index of the token in the allowed list.
    /// @return The collateral token address.
=======
    /// @notice Returns an allowed collateral token address by index.
    /// @param _index The index of the token in the allowed list.
    /// @return The token address.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    function getTokenAddress(uint256 _index) public view returns (address) {
        return s_TOKEN_ADDRESSES[_index];
    }

<<<<<<< HEAD
    /// @notice Returns a user's DSC debt specifically allocated to a single collateral token.
    /// @param _user The user's address.
    /// @param _token The collateral token address.
    /// @return The DSC debt (in 1e18) allocated to that token.
=======
    /// @notice Returns the address of a user who has deposited collateral by index.
    /// @param _index The index of the user in the tracking array.
    /// @return The user address.
    function getUsers(uint256 _index) public view returns (address) {
        return s_USERS[_index];
    }

    /// @notice Returns the total count of users who have deposited collateral.
    /// @return The count of users.
    function getUsersCount() public view returns (uint256) {
        return s_USERS.length;
    }

    /// @notice Returns a user's deposited collateral balance for a specific token.
    /// @param _user The user's address.
    /// @param _tokenAddress The collateral token address.
    /// @return The collateral amount.
    function getUserCollateralBalance(address _user, address _tokenAddress) public view returns (uint256) {
        return s_USERS_COLLATERAL_BALANCE[_user][_tokenAddress];
    }

    /// @notice Returns a user's total DSC debt across *all* collateral types.
    /// @param _user The user's address.
    /// @return The total DSC minted by the user.
    function getUserMintedDscBalance(address _user) public view returns (uint256) {
        return s_USER_MINTED_DSC[_user];
    }

    /// @notice Returns a user's DSC debt specifically allocated to a single collateral token.
    /// @param _user The user's address.
    /// @param _token The collateral token address.
    /// @return The DSC debt allocated to that token.
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    function getTokenToMintedDSC(address _user, address _token) public view returns (uint256) {
        return s_TOKEN_TO_MINTED_DSC[_user][_token];
    }

<<<<<<< HEAD
    /// @notice Returns a user's deposited collateral balance for a specific token.
    /// @param _user The user's address.
    /// @param _tokenAddress The collateral token address.
    /// @return The collateral amount (in its native token units).
    function getUserCollateralBalance(address _user, address _tokenAddress) public view returns (uint256) {
        return s_USERS_COLLATERAL_BALANCE[_user][_tokenAddress];
    }

=======
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
    /// @notice Returns the address of the DefiStableCoin contract.
    /// @return The DSC contract address.
    function getDSCAddress() public view returns (address) {
        return address(i_DSC);
    }
}

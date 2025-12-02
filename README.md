Decentralized Stablecoin Protocol (DSC)

The Decentralized Stablecoin Protocol (DSC) is a Solidity-based DeFi primitive designed to mint a USD-pegged stablecoin (DSC) against over-collateralized cryptocurrency assets (WETH, WBTC, etc.).

This implementation focuses on safety, solvency, and a novel collateral-specific debt tracking mechanism, ensuring that the health of a user's position is managed granularly per asset, thereby preventing catastrophic cross-collateral contagion.

⚙️ Architecture

The protocol is split into two core components:

DSCEngine.sol (Contract): The central hub. It manages user state (collateral balances, DSC debt), handles token transfers, enforces security checks, and exposes all external functions (deposit, mint, liquidate).

engineLibrary.sol (Library - Aliased as DSCLIB.sol): Contains all the pure and gas-efficient calculation logic. This includes fetching Chainlink prices, calculating the total USD value of collateral, and determining a user's health status ("Good!!!", "Warning!!!", "Risk!!!").

🔒 Solvency and Health Mechanics

The protocol enforces a dual-layered health check system to maintain over-collateralization at both the individual user and the global protocol level.

1. User Position Health

Each user's debt is mapped per collateral token. For example, debt minted against WETH is separate from debt minted against WBTC, allowing for precise risk management.

Minimum Collateralization Ratio (MCR): 150%

Risky Operations (Mint/Withdraw): Any action that would push a user's collateralization below 150% (Health Factor $\le 1.5$) will revert. Users must maintain $\ge 150\%$ collateralization to perform standard operations.

Liquidation Threshold: 120%

Grace Zone (120% to 150%): A user is considered in the Warning!!! zone. They cannot withdraw collateral but are not yet eligible for liquidation.

Liquidation Zone ($< 120\%$): If the health factor drops below 120% (Health Factor $< 1.2$), the position enters the Risk!!! zone and is eligible for liquidation.

$$\text{Health Factor} = \frac{\text{Total Collateral Value (USD)}}{\text{Total DSC Debt}}$$

2. Protocol Global Health

The entire system's solvency is checked after every major transaction (mint or collateral redeem) to prevent a global deficit.

Global Solvency Threshold: The total USD value of all collateral held by the protocol must be greater than $125\%$ of the total outstanding DSC supply.

💰 Liquidation Process

Liquidation is an external function designed to incentivize liquidators to resolve under-collateralized positions:

Eligibility: The debtor's health factor must be in the Risk!!! zone ($< 120\%$).

Repayment: The liquidator burns DSC to repay a portion of the debtor's debt.

Maximum Burn: A liquidator is restricted to burning $\le 50\%$ of the debtor's debt per collateral token in a single transaction, ensuring decentralized liquidation and preventing one-shot full takeovers.

Incentive: The liquidator is rewarded with the debtor's collateral plus a $10\%$ bonus on the seized value.

$$\text{Collateral Seized} = \left(\frac{\text{DSC Burned}}{\text{Collateral Price}}\right) \times 1.10$$

🔑 External Functions

Deposit and Mint

Function

Description

Pre-Check

Post-Check

depositCollateral(address token, uint256 amount)

Deposits collateral tokens.

onlyAllowedAddress, noneZero

None (safe operation).

mintDSC(address token, uint256 amount)

Mints DSC debt against a specific collateral.

noneZero

User Health $\ge 150\%$

depositCollateralForDSC(...)

Atomic deposit + mint.

(Combines checks)

User Health $\ge 150\%$ & Protocol Health

Redeem and Repay

Function

Description

Pre-Check

Post-Check

burnDSC(uint256 amount, address token)

Repays debt (burns DSC) against a specific collateral.

noneZero, sufficient debt

None (improves health).

redeemCollateral(address token, uint256 amount)

Withdraws deposited collateral.

noneZero, sufficient balance

Current User Health $\ge 150\%$ and Future User Health $\ge 150\%$.

redeemCollateralWithDSC(...)

Atomic burn + redeem.

(Combines checks)

Current User Health $\ge 150\%$ and Future User Health $\ge 150\%$.

Liquidation

Function

Description

Check

Result

liquidate(address token, address debtor, uint256 dscToBurn)

Liquidates a risky position.

Debtor Health $< 120\%$, Burn $\le 50\%$ of debt.

Collateral + 10% bonus transferred to liquidator; Debtor debt/collateral reduced.

### Security Features

✅ Reentrancy Protection (CEI pattern)
✅ Oracle Staleness Checks
✅ Forward-Looking Validation
✅ Protocol Insolvency Prevention
✅ Liquidation Safeguards
✅ Comprehensive Testing (19 unit + 4 invariant tests)

## Installation
```bash
git clone <your-repo-url>
cd dsc-stablecoin
forge install
```

## Usage

### Deploy
```bash
# Local
forge script script/DEFI-STABLECOIN.s.sol --rpc-url anvil --broadcast

# Sepolia
forge script script/DEFI-STABLECOIN.s.sol --rpc-url sepolia --broadcast --verify
```

### Run Tests
```bash
# All tests
forge test

# Invariant tests only
forge test --match-contract dscInvariantTest -vvv

# Coverage
forge coverage
```

### Interact
```solidity
// Deposit collateral
dscEngine.depositCollateral(wethAddress, 5 ether);

// Mint DSC (max 66.67% of collateral value)
dscEngine.mintDSC(wethAddress, 2000e18);

// Check health
(uint256 health, string memory status) = dscEngine.getHealth(wethAddress, user, 0);

// Redeem
dscEngine.redeemCollateralWithDSC(wethAddress, 1 ether, 1000e18);
```

## Test Results

<<<<<<< HEAD
**Unit Tests**: 19/19 passing
=======
**Unit Tests**: 20/20 passing
>>>>>>> 384f15a69b6364b09ca1da93ad5724330a5f3d67
**Invariant Tests**: 4/4 passing (12,800 calls, 0 reverts)

### Key Invariants Proven
1. Total collateral value >= Total DSC supply (always)
2. Sum of user DSC balances == Total DSC supply
3. All getter functions never revert

## How It Differs From Other Stablecoins

**MakerDAO (DAI)**: Uses vault-based system, DSC uses collateral-specific allocation
**Liquity (LUSD)**: Single collateral (ETH), DSC supports multiple with independent tracking
**Traditional Systems**: Allow cross-collateral insolvency, DSC prevents via granular health checks

## Novel Design Patterns

### Protocol Health Check
Before ANY transaction (mint/redeem), validates:
```
totalCollateralValue (WETH + WBTC) >= totalDSCSupply + pendingMint
```

This prevents protocol insolvency even if individual users maintain healthy positions.

### Collateral-Allocated Debt
```solidity
mapping(address user => mapping(address token => uint256)) s_TOKEN_TO_MINTED_DSC
```

Tracks which collateral backs which DSC, preventing:
- Over-minting against one collateral type
- Draining protocol through collateral manipulation
- Fast insolvency during price crashes

## Discovered Vulnerabilities (Fixed)

During invariant testing, discovered:
1. **Missing Protocol Health Check**: Users could mint more DSC than total collateral value
2. **Cross-Collateral Insolvency**: Summing both collaterals for health allowed gaming
3. **Unrealistic Fuzz Testing**: Default Foundry ranges caused false positives

All fixed via collateral-specific tracking and realistic bounds.

## Gas Optimization

- Uses `immutable` for DSC address
- Caches array lengths in loops
- Minimal storage reads via local variables
- Optimized for common paths (deposits/mints)

## Tech Stack

- **Solidity**: ^0.8.20
- **Foundry**: Testing and deployment
- **OpenZeppelin**: ERC20, Ownable
- **Chainlink**: Price oracles

## Repo Stats

- 600+ lines of Solidity
- 24 unit tests
- 4 invariant tests with custom handler
- 54%+ code coverage
- Zero known vulnerabilities

## License

MIT

## Author

Charles Onyii - Smart Contract Developer specializing in DeFi security and advanced Foundry testing

**Available for:** Protocol audits, invariant test design, DeFi development

GitHub: [github.com/cboi1019](https://github.com/cboi1019)

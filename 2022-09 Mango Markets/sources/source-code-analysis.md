# Source Code Analysis — Mango Markets

## Incident

Date:

11 October 2022

Protocol:

Mango Markets V3

Chain:

Solana

Estimated Value Extracted:

Approximately $116 million

Primary Vulnerability:

Oracle / market-price manipulation

## 1. Protocol Design

Mango Markets is a Solana-based margin trading and lending protocol.

Users can:

- deposit collateral,
- open leveraged positions,
- borrow assets,
- trade perpetual contracts,
- use unrealized profit as part of their account equity.

The protocol therefore depends heavily on accurate asset prices.

## 2. MNGO as Collateral

MNGO was supported by Mango's risk engine.

The value of MNGO affected the account's equity and therefore affected
the amount that could be borrowed.

This created a critical dependency:

    MNGO market price
          ↓
    Oracle price
          ↓
    Collateral valuation
          ↓
    Borrowing capacity

## 3. Thin Liquidity

MNGO had relatively low liquidity compared with the amount of capital
the attacker was able to deploy.

This meant that a large trader could move the market price substantially.

The attacker used multiple venues to increase the observed MNGO price.

## 4. Two-Account Strategy

The attacker used two Mango accounts.

Account A:

    Large MNGO-PERP long position

Account B:

    Opposite side of the MNGO-PERP position

The accounts were controlled by the same attacker.

The strategy allowed the attacker to establish a very large MNGO exposure
while simultaneously manipulating the market price used for valuation.

## 5. Price Manipulation

The attacker bought MNGO aggressively on relatively thin markets.

The MNGO price increased dramatically.

The manipulated market price was reflected in Mango's oracle/risk
calculations.

This caused the long position to show a very large unrealized profit.

## 6. Unrealized Profit

The attacker did not need to sell the MNGO position to realize its value
inside Mango's risk engine.

The increased oracle price caused the long position to have a much larger
mark-to-market value.

Conceptually:

    Position size × manipulated price
              =
    inflated unrealized PnL

The inflated PnL increased the account's effective equity.

## 7. Increased Borrowing Capacity

Mango's risk engine used the account's equity and collateral values when
determining borrowing capacity.

Therefore:

    Manipulated MNGO price
            ↓
    Inflated position value
            ↓
    Inflated equity
            ↓
    Increased borrowing capacity

## 8. Asset Extraction

The attacker borrowed and withdrew assets from Mango's shared liquidity.

The extracted assets included:

- USDC
- SOL
- BTC
- ETH
- USDT
- other supported assets

The total value was approximately:

    $116 million

## 9. Price Reversion

After the attacker had withdrawn the valuable assets, the MNGO price
returned toward its previous level.

The large MNGO position therefore no longer represented sufficient
economic value to support the outstanding borrowings.

The protocol was left with bad debt.

## 10. Root Cause

The root cause was not a conventional Solidity-style smart-contract bug.

It was an economic design weakness involving:

1. Low-liquidity collateral.
2. Manipulable price inputs.
3. Large leverage.
4. Use of unrealized PnL in risk calculations.
5. Insufficient protection against extreme price movements.

## 11. Oracle Risk

An oracle can be technically correct while still being economically
unsafe.

If an attacker can move the underlying market at a cost lower than the
borrowing capacity created by that price movement, the oracle becomes
an attack surface.

## 12. Vulnerability Classification

Primary:

- Oracle manipulation
- Price manipulation
- Economic exploit
- Collateral valuation failure

Secondary:

- Low-liquidity collateral
- Excessive leverage
- Unrealized PnL manipulation
- Cross-market manipulation

## 13. Was This a Flash Loan?

No.

The attacker used approximately $10 million of pre-funded capital
across two Mango accounts.

The attack should therefore NOT be classified as a flash-loan attack.

## 14. Preventive Measures

### A. Stronger Oracle Design

Use manipulation-resistant pricing mechanisms.

Possible approaches:

- long-window TWAP
- multi-source price aggregation
- independent external price feeds
- liquidity-weighted pricing
- maximum price deviation checks

### B. Conservative MNGO Risk Parameters

MNGO could have had:

- lower collateral weight,
- lower maximum borrowing capacity,
- stricter maintenance requirements,
- or no collateral support at all.

### C. Position Size Limits

The protocol could restrict the maximum size of a position relative
to market liquidity.

A position worth hundreds of millions of dollars should not be
possible in a market with only a few million dollars of meaningful
liquidity.

### D. Unrealized PnL Limits

Unrealized profits from highly manipulable markets should not immediately
translate into unrestricted borrowing power.

Possible protections include:

- discounted unrealized PnL,
- PnL caps,
- delayed recognition,
- independent liquidation pricing.

### E. Price Deviation Circuit Breaker

The protocol could reject or restrict borrowing when:

    current price

deviates too far from:

    reference price

within a short period.

### F. Trade Surveillance

A large MNGO position combined with unusual buying activity should have
triggered an automated risk alert.

## 15. Security Lesson

Oracle security must be evaluated economically, not only technically.

The key question is:

    How much does it cost to manipulate the oracle?

versus:

    How much additional borrowing capacity does the manipulated price
    create?

If the second number is much larger than the first, the protocol is
economically exploitable.
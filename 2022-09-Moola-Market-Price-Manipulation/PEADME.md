# Moola Market Price Manipulation — October 2022

## Incident

- Incident Date: 18 October 2022
- Protocol: Moola Market
- Chain: Celo
- Main Vulnerability: Price Manipulation
- Attack Venue: Ubeswap
- Manipulated Asset: MOO
- Estimated Loss: Approximately $8.4–9.1 million
- Recovered: Approximately 93.1%
- Attack Technique: Market Manipulation + Collateralized Borrowing

## Summary

On 18 October 2022, Moola Market was exploited through manipulation of
the price of its native MOO token.

The attacker identified that MOO had relatively low liquidity on Ubeswap.

The attacker first acquired CELO and used part of it to obtain MOO.

The attacker then repeatedly traded MOO against CELO on Ubeswap, causing
the market price of MOO to increase significantly.

Moola used a Ubeswap-based price feed for supported assets.

The inflated MOO price was therefore reflected in Moola's collateral
valuation.

The attacker used the artificially inflated MOO balance as collateral
to borrow large quantities of assets from Moola.

## Attack Flow

```text
Attacker
   |
   | CELO
   v
Ubeswap
   |
   | Buy MOO
   v
MOO price increases
   |
   v
Moola Oracle
   |
   | inflated MOO price
   v
Moola LendingPool
   |
   | MOO used as collateral
   v
Borrow:
   - CELO
   - cUSD
   - cEUR
   - MOO
   |
   v
Swap / extract assets
   |
   v
Protocol liquidity drained
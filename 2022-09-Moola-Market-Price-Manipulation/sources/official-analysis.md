# Official Analysis

## Moola Market Exploit

Date:

18 October 2022

Chain:

Celo

The Moola Market protocol was exploited through manipulation of the
market price of its native MOO token.

The attacker used the low liquidity of the MOO market on Ubeswap to
increase the apparent market value of MOO.

The manipulated MOO tokens were then used as collateral on Moola Market.

The attacker borrowed multiple assets against the inflated collateral
valuation.

## Attack

The attacker:

1. Acquired CELO.
2. Acquired MOO.
3. Manipulated the MOO/CELO market on Ubeswap.
4. Increased the apparent value of MOO.
5. Used MOO as collateral on Moola.
6. Borrowed CELO, cUSD, cEUR and MOO.
7. Extracted the borrowed assets.
8. Repeated the manipulation/borrowing process.

## Impact

Approximately $8.4–9.1 million was extracted.

Moola paused activity following the incident.

More than 93% of the exploited funds were subsequently returned.

## Remediation

Moola subsequently:

- removed MOO as a collateral asset,
- adjusted risk parameters,
- fixed oracle values at pre-attack levels during recovery,
- introduced additional safeguards before restoring normal protocol
  operation.
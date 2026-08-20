# Official / Primary Analysis — Mango Markets

## Incident

Date:

11 October 2022

Protocol:

Mango Markets

Network:

Solana

Approximate Loss:

$116 million

## Summary

Mango Markets was exploited through manipulation of the MNGO market price.

The attacker used two Mango accounts to establish opposing MNGO
perpetual positions.

The attacker then bought MNGO aggressively in relatively illiquid
markets.

The resulting increase in MNGO's reported price caused the attacker's
MNGO position to show a large unrealized profit.

This increased the account's borrowing capacity.

The attacker borrowed and withdrew approximately $116 million in assets
from Mango Markets.

After the withdrawals, the MNGO price returned toward its previous
level, leaving the protocol with a large undercollateralized position.

## Root Cause

The main weakness was the combination of:

- manipulable MNGO market pricing,
- low liquidity,
- MNGO collateral support,
- large leverage,
- and borrowing capacity based on inflated unrealized value.

## Impact

Approximately $116 million in assets were withdrawn.

Mango Markets subsequently froze the program and entered into a recovery
process.

Approximately $67 million was returned.

## Important Distinction

This was primarily an economic/oracle manipulation exploit.

It was not:

- a reentrancy attack,
- a private-key compromise,
- or a conventional flash-loan exploit.

The attacker used pre-funded capital.

## Prevention

The incident could have been mitigated through:

- more robust oracle aggregation,
- liquidity-aware collateral parameters,
- conservative MNGO collateral weights,
- limits on position size,
- unrealized-PnL restrictions,
- and automated price/position circuit breakers.
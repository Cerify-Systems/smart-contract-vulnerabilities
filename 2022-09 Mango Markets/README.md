# Mango Markets Price Oracle Manipulation — October 2022

## Incident

- Date: 11 October 2022
- Protocol: Mango Markets V3
- Chain: Solana
- Estimated Loss: ~$116 million
- Returned: ~$67 million
- Vulnerability: Oracle / Price Manipulation
- Main Asset: MNGO
- Attack Type: Economic Exploit

## Summary

On 11 October 2022, Mango Markets was exploited through manipulation
of the MNGO price used by the protocol's risk engine.

The attacker used two Mango accounts to establish opposing MNGO
perpetual positions.

The attacker then purchased MNGO aggressively in relatively thin
markets.

The resulting price increase inflated the value of the attacker's MNGO
position.

Because the position showed a large unrealized profit, the attacker's
borrowing capacity increased dramatically.

The attacker then borrowed and withdrew approximately $116 million
worth of assets from Mango Markets.

Once the MNGO price returned toward its previous level, the position
was no longer sufficiently collateralized.

## Attack Flow

```text
Account A
    |
    | Large MNGO long
    |
    +----------------------+
                           |
                           v
                    MNGO market
                           |
                    Price manipulation
                           |
                           v
                      Oracle price
                           |
                           v
                  Inflated MNGO value
                           |
                           v
                 Unrealized PnL increases
                           |
                           v
                Borrowing capacity rises
                           |
                           v
                $116M assets withdrawn
                           |
                           v
                    MNGO price falls
                           |
                           v
                     Bad debt
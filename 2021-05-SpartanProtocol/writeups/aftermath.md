# Aftermath

## Immediate Response

On 2 May 2021, Spartan Protocol publicly acknowledged an exploit targeting its liquidity pools and reported that more than $40M in assets had been drained based on prices at the time.

The project stated that the attacker used approximately $60M of BNB to create large imbalances in targeted pools and then exploited the liquidity-share calculation.

## Technical Investigation

The project worked with the community and PeckShield to analyze the attack transactions and identify the specific `calcLiquidityShare` vector.

The May development report states that an update to the Utils contract was subsequently deployed to prevent repeated attempts using the same vector.

## Additional Research

Amber Group independently reproduced the vulnerability and reported that additional user funds remained at risk while the remediation was being developed.

Its report describes a temporary patch that prevented liquidity removal, followed by a later final patch.

## Lessons for Protocol Development

The incident highlighted:

- the danger of using raw token balances in accounting;
- the need for symmetric mint/burn formulas;
- the importance of testing unsolicited transfers;
- the importance of mainnet-fork reproduction;
- the risks of upgradeable math/helper contracts;
- the need for rapid monitoring after an emergency patch.

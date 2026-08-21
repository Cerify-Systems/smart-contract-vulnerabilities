# Official Analysis — BonqDAO

## Incident

- Protocol: BonqDAO
- Launch: 15 December 2022
- Exploit: 1 February 2023
- Network: Polygon
- Attack Type: Oracle Price Manipulation

## Summary

On 1 February 2023, BonqDAO was exploited through a vulnerability in
the TellorPriceFeed implementation.

The attacker manipulated the reported WALBT price through TellorFlex.

The Bonq price feed immediately consumed the newly submitted value.

This allowed the attacker to temporarily make WALBT appear extremely
valuable.

The attacker used only 0.1 WALBT as collateral and borrowed approximately
100 million BEUR.

The attacker subsequently reduced the WALBT price to an extremely low
value.

This caused many existing WALBT-backed troves to become
undercollateralized.

The attacker liquidated more than 30 troves and acquired approximately
113 million WALBT.

## Root Cause

The vulnerable implementation used:

    oracle.getCurrentValue(queryId)

instead of using a historical value that had passed the Tellor dispute
window.

Bonq itself stated that the safer implementation should have used:

    getDataBefore(
        queryId,
        block.timestamp - 20 minutes
    )

## First Attack

The attacker:

1. Staked 10 TRB.
2. Submitted a manipulated WALBT price.
3. Created a WALBT trove.
4. Deposited 0.1 WALBT.
5. Borrowed approximately 100M BEUR.

## Second Attack

The attacker:

1. Submitted a very low WALBT price.
2. Caused existing WALBT troves to become undercollateralized.
3. Liquidated more than 30 troves.
4. Used BEUR to purchase the liquidated WALBT.
5. Withdrew the resulting assets.

## Impact

Reported losses included approximately:

    98.6M BEUR
    113.8M WALBT

The broader incident was commonly reported as approximately
$120 million in affected value.

## Remediation

The key remediation is to prevent newly submitted oracle values from
being consumed immediately.

The protocol should also use:

- delayed oracle values,
- multiple independent price sources,
- conservative collateral parameters,
- price-deviation limits,
- and emergency circuit breakers.
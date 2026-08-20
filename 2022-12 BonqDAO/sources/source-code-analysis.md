# Source Code Analysis — BonqDAO

## Incident

Protocol:

BonqDAO

Launch:

15 December 2022

Exploit:

1 February 2023

Network:

Polygon

Primary Vulnerability:

Oracle Price Manipulation

Affected Asset:

WALBT

Stablecoin:

BEUR

## 1. BonqDAO

BonqDAO was a zero-interest overcollateralized lending protocol.

Users could deposit supported assets as collateral and borrow BEUR,
a Euro-pegged stablecoin.

The value of collateral was determined using price feeds.

Therefore, the oracle was a critical security component.

## 2. Oracle Architecture

The relevant price flow was:

    WALBT
      |
      v
    TellorFlex
      |
      v
    TellorPriceFeed
      |
      v
    ConvertedPriceFeed
      |
      v
    Bonq Trove
      |
      v
    Collateral valuation

Tellor provided the WALBT/USD price.

ConvertedPriceFeed converted that value into a WALBT/EUR price.

The resulting price was used when determining how much BEUR could be
borrowed against WALBT collateral.

## 3. TellorPriceFeed

The vulnerable function was:

    price()

The implementation used:

    oracle.getCurrentValue(queryId)

This returns the latest submitted Tellor value.

The problem was that the latest value could be consumed immediately.

## 4. Missing Delay

Tellor's reporting mechanism requires a dispute period so that
incorrect submissions can be challenged.

Bonq's implementation did not respect that delay.

Instead of using an older confirmed value, it used:

    getCurrentValue()

immediately.

A safer approach would have been:

    getDataBefore(
        queryId,
        block.timestamp - 20 minutes
    )

This would prevent a newly submitted malicious value from being used
immediately.

## 5. Low Reporting Cost

At the time of the attack, the TellorFlex stake required to submit a
price was only:

    10 TRB

The attacker acquired and staked 10 TRB.

This allowed the attacker to become a Tellor reporter for the relevant
price query.

## 6. First Price Manipulation

The attacker submitted an extremely high WALBT price.

The reported value represented approximately:

    $5,000,000 per WALBT

The Bonq price feed immediately consumed the newly submitted value.

## 7. Inflated Collateral

The attacker created a WALBT trove.

Only approximately:

    0.1 WALBT

was deposited as collateral.

Because the oracle reported an extremely high WALBT price, the tiny
collateral amount appeared to be worth an enormous amount.

## 8. Borrowing

The attacker used the inflated collateral valuation to mint approximately:

    100,000,000 BEUR

The borrowed BEUR was not backed by economically equivalent collateral.

## 9. Second Price Manipulation

The attacker waited for a new reporting timestamp and then submitted
another WALBT price.

This time the price was extremely small:

    approximately $0.0000001

This caused existing WALBT-backed troves to become severely
undercollateralized.

## 10. Liquidations

The attacker used the BEUR obtained during the first phase to purchase
WALBT collateral from liquidated troves.

More than 30 troves were liquidated.

The attacker ultimately acquired approximately:

    113,000,000+ WALBT

## 11. Why the Attack Worked

The attack required the combination of:

    permissionless price reporting
            +
    low reporting stake
            +
    immediate price consumption
            +
    WALBT accepted as collateral
            +
    large borrowing capacity

The most important design mistake was consuming the latest Tellor value
without waiting for its dispute period.

## 12. Root Cause

The primary root cause was:

    TellorPriceFeed.getCurrentValue()

being used instead of a delayed historical value.

The oracle integration therefore allowed:

    submit price
        ↓
    use price immediately

instead of:

    submit price
        ↓
    wait for dispute period
        ↓
    use confirmed price

## 13. Vulnerability Classification

Primary:

- Oracle manipulation
- Price feed integration failure
- Insufficient oracle validation

Secondary:

- Excessive collateral valuation
- Permissionless price reporting
- Low oracle reporting cost
- Mass liquidation
- Bad debt

## 14. Prevention

### Delayed Oracle Consumption

Use:

    getDataBefore(
        queryId,
        block.timestamp - 20 minutes
    )

rather than:

    getCurrentValue(queryId)

### Multiple Price Sources

Use independent sources such as:

- Chainlink
- Tellor
- TWAP
- other independent market references

### Price Deviation Checks

Reject prices that deviate excessively from an independent reference.

### Conservative Collateral Parameters

WALBT should have had conservative collateral factors.

### Oracle Reporter Economics

The cost of manipulating the oracle should be meaningfully larger
than the economic benefit available through borrowing.

### Circuit Breakers

Large price movements should automatically pause borrowing and
liquidations involving the affected asset.

## 15. Security Lesson

A decentralized oracle is not automatically a safe oracle.

The protocol must understand:

- how values are submitted,
- who can submit them,
- how much it costs,
- how long they can be disputed,
- and when the protocol is allowed to consume them.

Using the newest oracle value immediately can completely defeat the
security assumptions of a dispute-based oracle.
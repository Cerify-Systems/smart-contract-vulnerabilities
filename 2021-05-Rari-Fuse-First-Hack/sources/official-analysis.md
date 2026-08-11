# Official Analysis

## Rari Capital Ethereum Pool Hack

Date:

8 May 2021

The Rari Capital Ethereum Pool was exploited through its integration with
Alpha Finance's ibETH pool.

Approximately 2,600 ETH was stolen, representing roughly 60% of the funds
held by the Rari Ethereum Pool at the time.

## Root Cause

Rari's Ethereum Pool used Alpha Finance's ibETH token as a yield-generating
strategy.

The value of the ibETH position was calculated using:

    ibETH.totalETH() / ibETH.totalSupply()

Rari was unaware that `ibETH.totalETH()` could be manipulated during the
execution of Alpha Homora's `work()` function.

The `work()` function also allowed user-controlled contracts to be called.

This allowed an attacker to:

1. Manipulate the Alpha pool's ETH accounting.
2. Re-enter Rari's deposit/withdrawal logic.
3. Cause Rari to calculate an inflated pool value.
4. Withdraw more ETH than should have been available.

## Response

Rari removed funds from Alpha in response to the attack and paused the
affected functionality.

Rari subsequently introduced additional safeguards for external protocol
integrations, including invariant checks and restrictions intended to reduce
the effectiveness of flash-loan-based attacks.
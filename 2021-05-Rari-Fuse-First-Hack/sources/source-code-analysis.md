# Source Code Analysis — Rari Capital May 2021

## Vulnerability

The May 2021 Rari Capital Ethereum Pool exploit was caused by an unsafe integration with Alpha Finance's ibETH pool.

The problem was not an isolated bug in the Rari token itself.

Rari relied on an external value from Alpha Finance:

    ibETH.totalETH()

Rari used this value to calculate the effective value of its ibETH holdings.

## Relevant Contracts

- RariFundManager.sol
- RariFundController.sol
- AlphaPoolController.sol
- Alpha Homora V1 Bank / ibETH

## Vulnerable Calculation

Rari's AlphaPoolController calculated the ETH value of its ibETH position approximately as:

    ibETH.balanceOf(RariFundController)
        * ibETH.totalETH()
        / ibETH.totalSupply()

This value was then used by RariFundManager when calculating:

- REPT tokens issued during deposits
- ETH returned during withdrawals

## External Assumption

Rari assumed that:

    ibETH.totalETH()

accurately represented the value of the Alpha pool.

This assumption was unsafe.

The Alpha Homora Bank contract allowed ETH to affect the value returned by `totalETH()`.

## Alpha Homora `work()`

The `work()` function could execute user-controlled strategy logic.

The attacker used this functionality to execute a malicious contract during the Alpha operation.

The malicious contract could:

1. Send ETH to the Alpha Bank.
2. Increase the Bank's ETH balance.
3. Increase the value returned by `totalETH()`.
4. Re-enter Rari's withdrawal logic.

## Reentrant Withdrawal

During the manipulated Alpha operation, the attacker called Rari's withdrawal functionality.

Rari queried the Alpha pool again.

Because `totalETH()` had been artificially increased, Rari calculated a larger ETH balance for its ibETH position.

The attacker could therefore redeem more ETH for the same amount of REPT.

## Simplified Formula

Before manipulation:

    Rari balance =
        ibETH shares
        × normal totalETH
        / totalSupply

During manipulation:

    Rari balance =
        ibETH shares
        × inflated totalETH
        / totalSupply

Therefore:

    inflated totalETH
        →
    inflated Rari pool balance
        →
    incorrect REPT/ETH exchange rate
        →
    excess ETH withdrawal

## Attack Sequence

1. Attacker obtains a large amount of ETH using a flash loan.
2. Attacker deposits ETH into Rari's Ethereum Pool.
3. Rari issues REPT tokens.
4. Attacker interacts with Alpha Homora's Bank.
5. The attacker manipulates the Bank's ETH balance.
6. `ibETH.totalETH()` becomes temporarily inflated.
7. The malicious contract calls Rari's withdrawal function.
8. Rari calculates its pool value using the inflated `totalETH()`.
9. The attacker receives more ETH than the REPT should represent.
10. The attacker repeats the process.
11. The flash loan is repaid.
12. Remaining ETH becomes the attacker's profit.

## Root Cause

The root cause was an unsafe cross-protocol assumption.

Rari treated a value supplied by an external protocol as a reliable accounting primitive.

The integration did not account for the fact that:

    totalETH()

could change during an external call.

## Vulnerability Classification

Primary:

- Cross-protocol integration vulnerability
- Manipulable accounting value
- Share-price manipulation

Secondary:

- Reentrancy
- Flash-loan-assisted attack
- External-call trust failure

## Important Security Lesson

A protocol must not blindly use an external protocol's accounting value as an authoritative asset valuation.

External calls can:

- change balances,
- change exchange rates,
- re-enter the caller,
- execute arbitrary user-controlled logic.

The integration must preserve its own accounting invariants even when the external protocol behaves unexpectedly.
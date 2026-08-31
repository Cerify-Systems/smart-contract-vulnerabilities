# Rari Capital Ethereum Pool Hack — May 2021

## Incident

- Date: 8 May 2021
- Protocol: Rari Capital
- Pool: Ethereum Pool
- Chain: Ethereum
- Loss: Approximately 2,600 ETH
- Approximate value: $10–11 million
- Vulnerability: Cross-protocol accounting manipulation
- Attack Technique: Flash Loan + Reentrancy + ibETH `totalETH()` Manipulation

## Summary

On 8 May 2021, the Rari Capital Ethereum Pool was exploited through its
integration with Alpha Finance's ibETH pool.

Rari deposited user ETH into Alpha's ibETH strategy.

The value of the ibETH position was calculated using:

    ibETH.totalETH() / ibETH.totalSupply()

The problem was that `ibETH.totalETH()` could be manipulated during the
execution of Alpha Homora's `work()` function.

The attacker used a flash loan to obtain temporary ETH and then used
Alpha's `work()` mechanism to manipulate the value returned by `totalETH()`.

The attacker then re-entered Rari's withdrawal logic.

Because Rari used the manipulated `totalETH()` value to calculate the value
of its ibETH holdings, the attacker could redeem more ETH than their REPT
balance should have allowed.

The attack was repeated until approximately 2,600 ETH had been drained.

## Attack Flow

```text
dYdX Flash Loan
      |
      v
Attacker
      |
      +--------------------+
      |                    |
      v                    v
 Rari Ethereum Pool   Alpha ibETH
      |                    |
      |                    |
      +---- REPT ----------+
                           |
                           v
                      Bank.work()
                           |
                           v
                 Manipulate totalETH()
                           |
                           v
                   Re-enter Rari
                           |
                           v
                     withdraw()
                           |
                           v
                Inflated pool value
                           |
                           v
                   Excess ETH
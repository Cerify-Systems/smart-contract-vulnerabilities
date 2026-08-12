# Alpha Homora / Iron Bank Exploit — February 2021

## Incident

- Date: 13 February 2021
- Protocol: Alpha Homora V2
- External Protocol: C.R.E.A.M. V2 Iron Bank
- Chain: Ethereum
- Loss: Approximately $37.5–38 million
- Vulnerability: Debt accounting manipulation + access-control weaknesses
- Attack Technique: Flash Loans + Rounding Error + Debt Share Manipulation
- Affected Component: HomoraBankV2
- Affected Pool: sUSD

## Summary

On 13 February 2021, Alpha Homora V2 was exploited through its
protocol-to-protocol lending relationship with C.R.E.A.M. V2 Iron Bank.

The exploit was possible because several weaknesses existed simultaneously
in HomoraBankV2.

An sUSD lending pool existed at the contract level even though it had not yet
been released through the Alpha user interface.

The pool had no liquidity.

This allowed the attacker to become the sole borrower and exploit a rounding
error in the debt-share calculation.

The attacker then used the permissionless `resolveReserve()` function to
increase `totalDebt` without proportionally increasing `totalDebtShare`.

This produced a highly distorted debt state.

The attacker repeatedly borrowed assets while keeping the recorded debt-share
impact extremely small.

The attacker then used Alpha Homora's Iron Bank integration to extract ETH
and stablecoins.

## Attack Flow

```text
Empty sUSD Pool
       |
       v
Attacker becomes sole borrower
       |
       v
Borrow sUSD
       |
       v
Repay 1 wei less
       |
       v
Residual debt share
       |
       v
resolveReserve()
       |
       v
totalDebt increases
totalDebtShare remains low
       |
       v
Repeated borrow operations
       |
       v
Debt grows dramatically
       |
       v
Alpha Homora
       |
       v
C.R.E.A.M. Iron Bank
       |
       v
ETH + DAI + USDC + USDT
       |
       v
Funds extracted
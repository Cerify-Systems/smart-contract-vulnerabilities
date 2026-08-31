# Akropolis Reentrancy Attack — November 2020

## Incident

- Date: 12 November 2020
- Protocol: Akropolis / Delphi
- Chain: Ethereum
- Loss: 2,030,841.0177 DAI
- Affected Pools: YCurve and sUSD
- Vulnerability: Reentrancy + Improper Token Validation
- Attack Technique: Flash Loan + Malicious ERC-20 Callback
- Exploiting Transactions: 17

## Summary

On 12 November 2020, Akropolis was exploited through a reentrancy
vulnerability in the Delphi SavingsModule.

The vulnerable `deposit()` function accepted token addresses without
sufficient validation and did not prevent reentrant execution.

The attacker created a malicious ERC-20-like token.

When the SavingsModule attempted to transfer this token using
`transferFrom()`, the malicious token executed a callback that called
`deposit()` again.

The second deposit used real DAI.

Because the original deposit was still executing, the nested deposit
changed the protocol balance before the outer deposit calculated its
final pool-token amount.

This caused the same DAI deposit to be effectively counted twice.

The attacker repeated the operation 17 times and drained approximately
2.03 million DAI.

## Attack Flow

```text
dYdX Flash Loan
       |
       v
Attacker
       |
       v
SavingsModule.deposit()
       |
       v
Malicious ERC20
       |
       | transferFrom()
       v
Attacker callback
       |
       v
SavingsModule.deposit()
       |
       v
Real DAI deposited
       |
       v
Pool tokens minted
       |
       v
Return to outer deposit
       |
       v
Balance difference includes
nested deposit
       |
       v
Additional pool tokens minted
       |
       v
Repeat
       |
       v
Withdraw pool tokens
       |
       v
~2.03M DAI drained
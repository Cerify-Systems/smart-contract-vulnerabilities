# Source Code Analysis — Akropolis Reentrancy

## Vulnerable Contract

The primary vulnerable contract was:

`SavingsModule.sol`

The vulnerable functionality was the `deposit()` function.

## Vulnerable Execution Flow

The relevant execution path was:

deposit()
    ↓
depositToProtocol()
    ↓
IERC20(token).safeTransferFrom()
    ↓
malicious token transferFrom()
    ↓
re-enter deposit()
    ↓
deposit real DAI
    ↓
return to original deposit()
    ↓
mint additional pool tokens

## 1. Deposit Entry Point

The attacker called:

`SavingsModule.deposit()`

The function accepted:

- protocol address
- token address
- token amount

The token address was supplied by the caller.

The contract did not sufficiently restrict this value to an approved token list.

## 2. Balance Calculation

Before transferring the deposit, `deposit()` calculated:

`nBalanceBefore`

After the transfer and protocol interaction, it calculated:

`nBalanceAfter`

The deposited amount was then derived from the difference:

`nDeposit = nBalanceAfter - nBalanceBefore`

The pool token amount was based on this accounting.

## 3. External Token Call

The function eventually executed:

`IERC20(tkn).safeTransferFrom(...)`

This was an external call to a token contract supplied by the caller.

An ERC-20 token implementation is normally expected to behave according to the token interface.

However, the attacker supplied a malicious token contract.

Its `transferFrom()` implementation contained a callback that re-entered Akropolis.

## 4. Reentrant Deposit

During the first deposit:

1. Attacker supplied the malicious token.
2. Akropolis called the malicious token's `transferFrom()`.
3. The malicious token executed its callback.
4. The callback called `SavingsModule.deposit()` again.
5. The second deposit used real DAI.
6. The second deposit completed normally.
7. Execution returned to the first deposit.

The first deposit had therefore not finished when the second deposit was executed.

## 5. Double Counting

The critical accounting issue was that the outer deposit calculated its result using a balance difference that included the effects of the nested deposit.

Suppose the attacker deposited:

25,000 DAI

during the reentrant call.

The nested deposit could receive approximately:

25,000 pool tokens.

When execution returned to the outer deposit, the changed balance was also used by the outer deposit's accounting.

This could result in approximately:

50,000 pool tokens

being credited for approximately:

25,000 DAI

of real value.

## 6. Fake Token

The attacker used a malicious ERC-20-like contract:

`0xe2307837524Db8961C4541f943598654240bd62f`

The malicious token was not a legitimate supported Akropolis asset.

Because the protocol did not properly validate the supplied token against its supported-token list, the attacker could use the token as the initial entry point.

## 7. Reentrancy Protection

The vulnerable `deposit()` implementation did not contain effective reentrancy protection.

There was no `nonReentrant` guard preventing:

`deposit() → token.transferFrom() → deposit()`

from occurring.

## 8. Root Cause

Two weaknesses worked together:

1. Insufficient validation of the deposited token.
2. Missing reentrancy protection around the deposit flow.

Neither weakness alone explains the complete exploit.

Together they allowed an attacker-controlled token contract to re-enter `deposit()` and manipulate pool-token accounting.

## 9. Attack Repetition

The attacker repeated the reentrant process multiple times.

PeckShield identified 17 exploiting transactions.

The total amount drained was:

2,030,841.0177 DAI

## 10. Vulnerability Classification

Primary:

- Reentrancy
- Cross-function reentrancy
- Improper token validation

Secondary:

- Accounting manipulation
- Untrusted external token callback
- Flash-loan-assisted attack

## 11. Security Lesson

External token calls must be treated as untrusted external calls.

A contract should:

1. Validate supported token addresses.
2. Protect sensitive entry points with reentrancy guards where appropriate.
3. Follow Checks-Effects-Interactions.
4. Avoid calculating accounting values across an untrusted external call.
5. Maintain accounting invariants even if a token implementation is malicious.
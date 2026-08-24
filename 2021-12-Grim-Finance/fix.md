# Fix

## Remove the vulnerable entry point

Grim's post-incident update states that the exploited `depositFor()` function was removed from the vault contract. This directly eliminated the vulnerable arbitrary-token deposit path. 

## Validate deposit assets

A vault should not allow the caller to choose an arbitrary token contract for a deposit. The accepted asset should be fixed by the vault or restricted to a trusted allowlist. This prevents an attacker from supplying a token whose transfer function executes arbitrary callback logic.

## Follow checks-effects-interactions

Internal accounting should be updated before interacting with an untrusted external contract whenever the architecture permits it. If an external token call is unavoidable, the function should be protected against reentrancy and its accounting must remain correct under nested execution.

## Add reentrancy protection

A `nonReentrant` guard should protect deposit and withdrawal entry points where external token or strategy calls can occur. CEI and reentrancy protection should be treated as complementary controls.

## Test malicious tokens

Regression tests should deploy a token whose `transferFrom()` calls back into `depositFor()`. The vault must not mint additional shares during that callback. Tests should also verify that arbitrary token addresses are rejected and that share supply remains consistent with actual vault assets.
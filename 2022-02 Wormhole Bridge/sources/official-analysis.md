# Official Analysis — Wormhole Bridge

## Incident

Date:

2 February 2022

Protocol:

Wormhole

Affected Chain:

Solana

Estimated Value:

Approximately $326 million

Asset:

120,000 wETH

## Summary

On 2 February 2022, an attacker exploited a vulnerability in the
Solana-side Wormhole bridge.

The attacker bypassed the Guardian signature verification mechanism
and caused Wormhole to mint 120,000 wETH on Solana without the
corresponding ETH being locked on Ethereum.

## Root Cause

The vulnerability was related to validation of the Solana instructions
sysvar used during signature verification.

Wormhole's `verify_signatures()` function relied on instructions from
the transaction to verify the Guardian signatures.

The attacker was able to provide a forged instructions-sysvar account
because the vulnerable code did not sufficiently verify that the
account was the genuine Solana sysvar.

This allowed the attacker to make a forged instruction appear to be a
valid secp256k1 signature-verification instruction.

## Attack

The attacker:

1. Constructed a malicious Wormhole message.
2. Created forged signature-verification data.
3. Supplied a forged instructions-sysvar account.
4. Passed the forged data to `verify_signatures()`.
5. Caused Wormhole to create a SignatureSet.
6. Submitted the forged VAA.
7. Passed the VAA through the token bridge.
8. Minted 120,000 wETH on Solana.
9. Bridged the newly created wETH back toward Ethereum.

## Impact

Approximately $326 million worth of value was created without
corresponding collateral on Ethereum.

Jump Crypto subsequently supplied 120,000 ETH to fully back the
Wormhole-wrapped ETH supply.

## Important Point

The attack did not involve compromising Wormhole Guardian private keys.

The failure occurred in the smart contract's validation of the
signature-verification environment.
# Wormhole Bridge Exploit — February 2022

## Incident

- Date: 2 February 2022
- Protocol: Wormhole
- Chains: Solana / Ethereum
- Estimated Loss: ~$326 million
- Unauthorized Mint: 120,000 wETH
- Vulnerability: Signature Verification Bypass
- Affected Component: Solana Wormhole Core Program

## Summary

On 2 February 2022, Wormhole suffered one of the largest bridge exploits
in cryptocurrency history.

The attacker exploited a vulnerability in the Solana-side Wormhole
core program.

The vulnerability allowed the attacker to bypass the Guardian signature
verification mechanism.

The attacker created a forged cross-chain message claiming that ETH had
been locked on Ethereum.

Wormhole accepted the forged authorization and minted:

    120,000 wETH

on Solana.

The attacker then bridged the newly minted wETH toward Ethereum.

## Attack Flow

```text
Attacker
    |
    v
Forge VAA/message
    |
    v
Forge secp256k1 instruction
    |
    v
Forge instructions-sysvar account
    |
    v
verify_signatures()
    |
    | forged signature verification accepted
    v
SignatureSet
    |
    v
post_vaa()
    |
    v
complete_transfer()
    |
    v
120,000 wETH minted on Solana
    |
    v
Bridge wETH toward Ethereum
    |
    v
~$326M unauthorized value
# Source Code Analysis — Wormhole Bridge

## Incident

Date:

2 February 2022

Protocol:

Wormhole

Chains:

Solana ↔ Ethereum

Estimated Loss:

Approximately $326 million

Asset:

120,000 wETH

Primary Vulnerability:

Signature verification bypass

## 1. Wormhole Architecture

Wormhole is a cross-chain messaging protocol.

For token transfers, Guardians observe activity on one blockchain and
produce a Verifiable Action Approval (VAA).

The destination chain verifies the VAA before executing the requested
action.

The security model therefore depends heavily on:

- Guardian signatures
- Guardian set validation
- VAA verification
- replay protection

## 2. Guardian Set

At the time of the incident, Wormhole used 19 Guardians.

A supermajority of the Guardian set was required for a VAA.

The attacker did not compromise the Guardian private keys.

Instead, the attacker bypassed the Solana-side signature verification
logic.

## 3. verify_signatures()

The vulnerable function was:

    verify_signatures()

This function processed the signatures associated with a VAA.

On Solana, Wormhole relied on the native secp256k1 verification
instruction.

Instead of performing the elliptic-curve verification entirely inside
the Wormhole program, Wormhole inspected a previous instruction in the
same transaction.

This was accessed through Solana's instructions sysvar.

## 4. Instructions Sysvar

The instructions sysvar contains information about the instructions
being executed in the current transaction.

Wormhole expected the account supplied to `verify_signatures()` to be
the genuine Solana instructions sysvar.

The vulnerable implementation did not sufficiently validate that this
account was actually the official instructions sysvar.

## 5. Missing Validation

The vulnerable code used an instruction-loading path that allowed the
attacker-controlled account to be interpreted as the instructions
sysvar.

The program then read a previous instruction from that account.

The attacker controlled the contents of the forged account.

## 6. Fake secp256k1 Instruction

The attacker constructed data that looked like a valid secp256k1
verification instruction.

The forged data represented signatures that appeared to correspond to
the required Guardians.

The attacker therefore did not need to obtain the private keys of the
real Wormhole Guardians.

## 7. SignatureSet

The `verify_signatures()` instruction created a SignatureSet representing
the signatures that had supposedly been verified.

Because the forged instructions sysvar was accepted, the SignatureSet
incorrectly indicated that sufficient Guardian signatures existed.

## 8. post_vaa()

The attacker then submitted the forged VAA through:

    post_vaa()

The VAA represented a token transfer that supposedly originated from
Ethereum.

The bridge accepted the SignatureSet as evidence that the VAA had
received the required Guardian signatures.

## 9. Token Mint

The forged VAA ultimately reached the token-transfer logic.

The attacker caused:

    120,000 wETH

to be minted on Solana.

These tokens were not backed by an equivalent amount of ETH locked on
Ethereum.

## 10. Bridging Back to Ethereum

The attacker then transferred the newly created wETH through the
legitimate Wormhole bridge path.

The attacker converted the resulting assets into ETH on Ethereum.

This turned the forged Solana-side authorization into real economic
value.

## 11. Root Cause

The root cause was insufficient validation of the instructions sysvar
used by the Solana-side signature verification mechanism.

The bridge trusted transaction metadata supplied through an account
without sufficiently proving that the account was the genuine Solana
instructions sysvar.

## 12. What Was NOT Compromised

The attacker did not:

- steal Guardian private keys,
- compromise the Guardian network,
- obtain real Guardian signatures,
- break the secp256k1 cryptographic algorithm.

The failure occurred in the bridge's logic for validating the
environment in which signature verification was supposed to occur.

## 13. Vulnerability Classification

Primary:

- Signature verification bypass
- Improper account validation
- Solana sysvar validation failure
- Cross-chain authorization bypass

Secondary:

- Unauthorized token minting
- Bridge accounting failure
- Cross-chain trust failure

## 14. Remediation

The vulnerable instruction-sysvar handling was changed so that the
program verifies the authenticity/ownership of the instructions sysvar
before reading instructions from it.

The verification path was updated to use the checked instruction-loading
mechanism.

The bridge also strengthened its verification and monitoring mechanisms
after the incident.

## 15. Security Lesson

When a smart contract relies on special runtime-provided accounts,
the contract must verify that those accounts are actually the expected
runtime accounts.

Never assume that an account supplied by a transaction caller is
trustworthy simply because its contents have the expected structure.

For security-sensitive operations:

    validate account identity
        +
    validate account ownership
        +
    validate instruction origin
        +
    validate cryptographic proof

must all be treated as separate security requirements.
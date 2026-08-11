# Nomad Bridge Hack — Root Cause Analysis

## Incident Overview

- **Protocol:** Nomad Bridge
- **Date:** August 1, 2022
- **Category:** Cross-chain bridge / message authentication
- **Impact:** More than $190 million drained
- **Primary affected chain:** Ethereum
- **Root cause:** Incorrect validation of whether a cross-chain message had been proven
- **Affected contract:** `Replica.sol`

On August 1, 2022, the Nomad Bridge was exploited due to a vulnerability in the `Replica` contract that caused the contract to incorrectly accept messages that had never been proven.

The vulnerability allowed attackers to forge cross-chain messages and cause the Nomad BridgeRouter to process unauthorized withdrawals. After the first exploit, others quickly copied the calldata, swapped the recipient address, and submitted their own fraudulent withdrawals.

## Background

Nomad is a cross-chain interoperability protocol that moves messages and assets between different blockchains.

The system uses:

- a **Home contract** on the source chain
- a **Replica contract** on the destination chain

Messages are committed to a Merkle tree on the source chain. The Merkle root is propagated to the destination chain using Nomad's optimistic verification mechanism.

The destination `Replica` contract must verify that an incoming message was included in an accepted Merkle root before processing it.

Therefore, security depends on the Replica correctly distinguishing between:

- a message that has been proven against a valid Merkle root, and
- a message that has never been proven.

## Root Cause

The vulnerability was caused by an unexpected interaction between three parts of `Replica.sol`:

1. `messages` mapping: stores the Merkle root for each proven message
2. `confirmAt` mapping: stores when a Merkle root becomes valid
3. `acceptableRoot()` function: checks whether a root is valid

### Message-to-root mapping

The contract stores the Merkle root under which each message was proven:

```solidity
mapping(bytes32 => bytes32) public messages;
```

When a message has not been proven, its mapping entry has never been written:

```solidity
messages[unprovenMessageHash] == bytes32(0)
```

Because Solidity returns default values for uninitialized mapping keys, an unproven message is represented by the zero root.

### Acceptable root check

The contract also tracks when each root becomes valid:

```solidity
mapping(bytes32 => uint256) public confirmAt;
```

The validation code was:

```solidity
function acceptableRoot(bytes32 _root) public view returns (bool) {
    // backwards compatibility for previous versions
    if (_root == LEGACY_STATUS_PROVEN) return true;
    if (_root == LEGACY_STATUS_PROCESSED) return false;

    uint256 _time = confirmAt[_root];

    if (_time == 0) {
        return false;
    }

    return block.timestamp >= _time;
}
```

Normally, an unknown root has `confirmAt[_root] == 0` and is rejected.

### Initialization bug

When a `Replica` contract is initialized, the initial committed root is pre-approved so that historical messages can be processed without replaying the full tree:

```solidity
function initialize(
    uint32 _remoteDomain,
    address _updater,
    bytes32 _committedRoot,
    uint256 _optimisticSeconds
) public initializer {
    __NomadBase_initialize(_updater);

    entered = 1;
    remoteDomain = _remoteDomain;
    committedRoot = _committedRoot;

    // pre-approve the committed root
    confirmAt[_committedRoot] = 1;

    _setOptimisticTimeout(_optimisticSeconds);
}
```

The bug occurred when `_committedRoot == bytes32(0)`.

A newly deployed Home contract starts with an empty Merkle tree, whose root is `bytes32(0)`. When the Replica was deployed simultaneously, initialization executed:

```solidity
confirmAt[bytes32(0)] = 1;
```

That made the zero root an accepted root.

### How the bug became exploitable

For an unproven message:

```text
messages[_messageHash] == bytes32(0)
```

The process function then evaluated:

```solidity
acceptableRoot(messages[_messageHash])
```

which became:

```solidity
acceptableRoot(bytes32(0))
```

Inside `acceptableRoot()`:

```solidity
uint256 _time = confirmAt[bytes32(0)];
```

Since initialization set `confirmAt[bytes32(0)] = 1`, the result was:

```solidity
_time = 1
```

Because `_time != 0`, the function continued and returned:

```solidity
block.timestamp >= _time
```

which is always true for valid blocks.

Therefore:

```solidity
acceptableRoot(bytes32(0)) == true
```

This meant that an unproven message could pass the proof check.

### Vulnerable process check

The `process()` function used `acceptableRoot()` to enforce proof status:

```solidity
function process(bytes memory _message) public returns (bool _success) {
    // ...
    require(
        acceptableRoot(messages[_messageHash]),
        "!proven"
    );
    // ...
}
```

Because `messages[_messageHash]` returned `bytes32(0)` for unproven messages, and `confirmAt[bytes32(0)]` was set to `1`, the unproven message was accepted.

## Attack Flow

1. Attacker constructs a forged cross-chain message.
2. The message has never been proven.
3. `messages[_messageHash]` resolves to `bytes32(0)`.
4. `acceptableRoot(bytes32(0))` checks `confirmAt[bytes32(0)]`.
5. `confirmAt[bytes32(0)]` is `1` because of initialization.
6. `acceptableRoot()` returns `true`.
7. `process()` accepts the message.
8. The bridge processes the fraudulent message.
9. Unauthorized withdrawals occur.

No valid Merkle proof was required.

## Why the attack spread rapidly

- The first exploit appeared at Ethereum block `15259101` on August 1, 2022.
- Attackers observed exploit calldata, copied it, replaced the recipient address, and replayed it.
- The exploit led to hundreds of transactions and dozens of individual withdrawals.
- The total loss exceeded $190 million.

## Upgrade history and regression

The vulnerable behavior was introduced in an upgrade deployed on June 21, 2022.

Before the upgrade, the contract used a stricter check:

```solidity
require(
    messages[_messageHash] == MessageStatus.Proven,
    "!proven"
);
```

That required the message to have an explicit `Proven` status.

The new design instead stored the Merkle root for the message and validated the root using `acceptableRoot()`:

```solidity
require(
    acceptableRoot(messages[_messageHash]),
    "!proven"
);
```

This change was intended to prevent a fraudulent updater from blocking valid messages. But it introduced the dangerous interaction between:

- `messages[_messageHash] == bytes32(0)`
- `confirmAt[bytes32(0)] == 1`

## Timeline

- **May 2022:** Relevant Replica upgrade development and audit.
- **June 9, 2022:** Quantstamp audit report finalized.
- **June 21, 2022:** Vulnerable upgrade deployed to Ethereum, Moonbeam, Evmos, Avalanche, Gnosis Chain, Milkomeda C1.
- **August 1, 2022:** Nomad Bridge exploited.
- **August 5, 2022:** Nomad published root-cause analysis.
- **August 15, 2022:** Nomad reported more than $33 million returned by whitehat hackers.

## Impact

The vulnerability caused the Replica contract to fail to properly authenticate inbound cross-chain messages.

As a result:

- arbitrary messages could be forged,
- forged messages could pass the `!proven` check,
- contracts relying on the Replica could receive fraudulent messages,
- the BridgeRouter processed unauthorized withdrawals.

Losses exceeded $190 million.

## Why watchers did not prevent the attack

Nomad's Watchers were designed to monitor compromises of the Updater key.

This attack did not require compromising or forging the Updater signature. Instead, it exploited a smart-contract validation bug in `Replica`.

Therefore, the Watcher mechanism did not trigger.

## Security invariant

The security invariant that should have held is:

> An inbound message must not be processed unless it has previously been proven against an accepted Merkle root.

A simplified assertion would be:

```solidity
assert(messages[_messageHash] != bytes32(0));
```

More precisely, processing should only succeed if the message resolves to a genuinely proven and accepted root.

## Fix

The patch prevents the zero root from being automatically confirmed during initialization.

The corrected logic is:

```solidity
if (_committedRoot != bytes32(0)) {
    confirmAt[_committedRoot] = 1;
}
```

This avoids creating:

```solidity
confirmAt[bytes32(0)] = 1;
```

With that fix, an unproven message resolving to `bytes32(0)` will have:

```solidity
confirmAt[bytes32(0)] == 0
```

and `acceptableRoot()` will correctly return `false`.

## Key takeaway

The Nomad Bridge exploit shows that security failures often come from the interaction of multiple components:

- default mapping values,
- initialization state,
- root validation logic,
- message-processing checks.

Analyzing each check in isolation is not enough. The zero value `bytes32(0)` had a special semantic meaning in multiple places, and the combination of those meanings caused the exploit.

## References

- Nomad — "Nomad Bridge Hack: Root Cause Analysis"
- Nomad GitHub Repository: https://github.com/nomad-xyz/monorepo
- Nomad Replica.sol: https://github.com/nomad-xyz/monorepo/blob/main/packages/contracts-core/contracts/Replica.sol
- Quantstamp audit documentation
- Independent analyses of the Nomad Bridge exploit

## Additional details

- Vulnerable Replica.sol - commit id: `b80ba83755a43e046c65d303d087094b58e8da9`
- Audited Replica.sol - commit id: `0e02cc1f09d16f809f5d2d8f05abbeea6d1af04e`
- Hack Analysis: https://immunefi.com/blog/bug-fix-reviews/hack-analysis-nomad-bridge-august-2022/

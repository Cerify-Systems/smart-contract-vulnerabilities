# Source Code Analysis — Beanstalk Governance Attack

## Vulnerable Component

The main vulnerable function was `GovernanceFacet.emergencyCommit()`.

```solidity
function emergencyCommit(uint32 bip) external {
    require(isNominated(bip));
    require(block.timestamp >= emergencyPeriod);
    require(isActive(bip));
    require(
        bipVotePercent(bip) >= emergencyThreshold
    );

    _execute(msg.sender, bip, false, true);
}
```

## Vulnerability

Beanstalk allowed voting power to be temporarily increased through deposits. The attacker used flash loans to obtain a huge amount of assets, deposited them into Beanstalk, and gained enough voting power to satisfy the emergency governance threshold.

## Attack Flow

```text
Flash Loan
    ↓
Deposit assets into Beanstalk
    ↓
Obtain large voting power
    ↓
Vote for malicious BIP-18
    ↓
emergencyCommit(BIP-18)
    ↓
Malicious proposal execution
    ↓
Transfer protocol assets
    ↓
Repay flash loan
```

## Root Cause

The governance system did not sufficiently prevent **temporary, flash-loan-funded voting power** from being used for immediate governance execution.

The proposal execution mechanism also allowed powerful logic to be executed using `delegatecall`.

## Impact

Approximately **$77 million in non-Bean assets** were stolen.

## Key Lesson

Governance systems should use mechanisms such as voting delays, vote locking, timelocks, or snapshot-based voting to prevent temporary capital from controlling governance.

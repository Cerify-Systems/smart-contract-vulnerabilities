# Beanstalk Governance Attack — Postmortem

## Date

**April 17, 2022**

## What Happened?

An attacker exploited Beanstalk's governance system by using flash loans to temporarily obtain enough voting power to pass a malicious governance proposal.

## Attack

1. Attacker obtained large flash loans.
2. Deposited assets into Beanstalk.
3. Obtained significant voting power.
4. Executed malicious **BIP-18** through `emergencyCommit()`.
5. Protocol assets were transferred to the attacker.
6. Flash loans were repaid.

## Root Cause

The protocol allowed temporary capital to generate sufficient governance power without requiring a long-term commitment.

## Impact

Approximately **$77 million in non-Bean assets** were stolen.

## Fix

Beanstalk removed the vulnerable autonomous on-chain governance mechanism and moved governance toward Snapshot voting with execution through a Community Multisig.

## Main Lesson

Flash-loanable voting power combined with powerful governance execution can lead to complete protocol compromise.

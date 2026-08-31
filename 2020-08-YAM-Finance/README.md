# YAM Finance – Rebase / Governance Bug (2020)

## Overview

YAM Finance was a DeFi protocol launched in August 2020 that combined elastic token supply, yield farming, and on-chain governance.

A critical bug in the YAMv1 rebasing mechanism caused the protocol to mint a vastly excessive amount of YAM tokens during the first rebase. The resulting increase in token supply made the governance quorum effectively unreachable, preventing the protocol from executing corrective governance proposals.

## Background

YAM used a rebasing mechanism to adjust its token supply based on the value of its underlying assets.

The rebasing calculation relied on a scaling factor. However, the original YAMv1 implementation omitted a required division by `BASE`.

The vulnerable calculation was:

```solidity
totalSupply = initSupply.mul(yamsScalingFactor);
# Official Postmortem

## Summary

YAM Finance launched in August 2020 as an experiment combining fair farming, elastic supply, and decentralized governance.

On August 12, 2020, the YAM team discovered a critical bug in the rebasing mechanism. The bug caused the protocol to mint far more YAM than intended into the protocol reserves.

The excess YAM made it impossible for governance proposals to reach the required quorum. As a result, the protocol could no longer execute governance actions and the treasury became effectively locked.

## Root Cause

The vulnerable calculation in the rebasing contract was:

```solidity
totalSupply = initSupply.mul(yamsScalingFactor);
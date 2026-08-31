# Source Code Analysis

## Vulnerable Component

The vulnerability was present in the YAMv1 rebasing mechanism.

YAM used a scaling factor to calculate the change in token supply during each rebase.

## Vulnerable Code

The vulnerable calculation was:

```solidity
totalSupply = initSupply.mul(yamsScalingFactor);
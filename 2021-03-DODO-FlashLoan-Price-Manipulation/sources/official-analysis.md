# Official / Primary Analysis

## DODO Postmortem

DODO published a postmortem describing the March 2021 Crowdpooling incident.

The incident involved multiple attackers and affected several DODO V2 Crowdpooling pools.

The postmortem explains the recovery effort and subsequent security improvements.

## Core Technical Finding

The Crowdpooling initialization mechanism allowed the pool to be initialized more than once.

This allowed attackers to:

- initialize a pool with a counterfeit token,
- modify the reserve state,
- reinitialize the pool using a real token,
- use flash-loan liquidity to extract the real assets.

## Security Remediation

DODO subsequently strengthened initialization and access-control mechanisms and subjected the Crowdpooling implementation to additional security audits.
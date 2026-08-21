# DODO Flash Loan / Crowdpooling Initialization Attack — March 2021

## Incident

- Date: 8 March 2021
- Protocol: DODO
- Component: DODO V2 Crowdpooling
- Chain: Ethereum
- Loss: Approximately $3.8 million
- Recovered: Approximately $3.1 million
- Vulnerability Type: Improper Initialization / Access Control
- Attack Technique: Flash Loan + Pool Reinitialization
- Affected Pools: WSZO, WCRES, ETHA and FUSI

## Summary

On 8 March 2021, several DODO V2 Crowdpooling pools were exploited.

The vulnerable Crowdpooling contract allowed its `init()` function to be invoked more than once. An attacker could therefore change the token configuration of an already initialized pool.

The attack involved:

1. Creating a counterfeit token.
2. Initializing the vulnerable pool with the counterfeit token.
3. Calling `sync()` so that the pool's reserve state reflected the counterfeit token balance.
4. Reinitializing the pool with a real token held by the DODO pool.
5. Using a flash loan to remove the real tokens while bypassing the pool's expected balance checks.

The vulnerability affected the Crowdpooling component rather than DODO's normal trading pools.

## Impact

The attack drained approximately $3.8 million worth of assets from affected Crowdpooling pools.

DODO reported that approximately $3.1 million was subsequently recovered.

## Root Cause

The root cause was insufficient access control around contract initialization.

The Crowdpooling pool was intended to be initialized once. However, the vulnerable implementation did not correctly prevent an external caller from invoking the initialization logic again.

This allowed the attacker to replace important pool configuration such as the base and quote token addresses.

## Why the Flash Loan Was Important

The flash loan supplied the attacker with the temporary capital required to interact with the real token reserves.

The important vulnerability was not the existence of flash loans themselves. The flash loan became effective because the attacker could manipulate the pool's initialization and reserve accounting within the same transaction.

## Affected Contracts

The affected component was the DODO V2 Crowdpooling implementation.

The relevant implementation contract is:

`CP.sol`

The post-incident DODO repository contains the Crowdpooling implementation and its supporting contracts.

## References

See `sources/references.md` for the original DODO repository, transaction records and incident analyses.
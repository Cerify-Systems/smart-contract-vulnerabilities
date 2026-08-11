# Source Code Analysis — DODO Crowdpooling

## Relevant Contract

The affected component was the DODO V2 Crowdpooling implementation:

`contracts/CrowdPooling/impl/CP.sol`

The contract is responsible for initializing Crowdpooling instances.

## Initialization Function

The important function is:

`init(...)`

It receives configuration for:

- owner
- maintainer
- base token
- quote token
- permission manager
- fee-rate model
- pool factory
- campaign timeline
- pool parameters
- TWAP configuration

The function subsequently stores these values in the Crowdpooling contract.

## Security-Critical Property

The initialization function must only execute once.

The vulnerable implementation failed to enforce this property correctly.

Because the token addresses were assigned during initialization, repeated initialization allowed the attacker to change the assets associated with the pool.

## Security Boundary

The important state variables include:

- `_INITIALIZED_`
- `_OWNER_`
- `_BASE_TOKEN_`
- `_QUOTE_TOKEN_`
- `_POOL_FACTORY_`
- `_POOL_QUOTE_CAP_`
- `_TOTAL_BASE_`

The attacker specifically benefited from being able to alter token-related state after the pool had already been initialized.

## Patched Design

The later DODO implementation uses initialization protection through `InitializableOwnable`.

The initialization flow includes:

`initOwner(address newOwner)`

and uses an initialization guard based on `_INITIALIZED_`.

This prevents initialization from being performed repeatedly.

## Vulnerability Classification

Primary:

- Improper Access Control
- Improper Initialization
- State Reinitialization

Secondary:

- Flash Loan Abuse
- Reserve Accounting Manipulation

The incident should therefore not be classified primarily as a conventional oracle-price manipulation vulnerability.
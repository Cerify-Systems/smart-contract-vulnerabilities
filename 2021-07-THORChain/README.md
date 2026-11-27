# THORChain — July 2021 ETH Router/ Bifrost Exploits

## Incident Overview

THORChain suffered multiple Ethereum-side security incidents in July 2021. This case study focuses on the July 2021 ETH Router incidents, especially the second exploit that resulted in approximately $8 million of economically significant ERC-20 assets being drained. THORChain's own post-mortem explains that the attacker created a fake router and used the Router's vault-transfer functionality to produce a deposit event that the Ethereum Bifrost interpreted as a legitimate deposit. The resulting malicious memo caused funds to be refunded to the attacker.

A separate July 16 exploit also used a wrapper contract in front of the Router. In that incident, the Bifrost used the transaction's `msg.value` instead of the actual deposit amount emitted by the Router, allowing the attacker to report ETH that had not actually been deposited. THORChain's post-mortem attributes the deeper root cause to the interface between the Router and the Bifrost: the off-chain observer did not sufficiently constrain what could be manipulated by a caller-controlled contract and transaction context.

This repository concentrates on the Solidity-side attack surface while explicitly documenting that the July 2021 loss was not caused by a single Solidity statement in isolation. The security failure crossed the boundary between the Ethereum Router and the Bifrost parser.

## Primary Contract

The principal Solidity contract is `THORChain_Router` (Router V2), deployed at:

`0xc145990e84155416144c532e31f89b840ca8c2ce`

The source was verified on Etherscan and was submitted for verification on July 10, 2021. The relevant functions include `deposit`, `depositWithExpiry`, `transferAllowance`, `transferOut`, and `returnVaultAssets`.

The actual vulnerable system also included the Ethereum Bifrost scanner. That component is written in Go rather than Solidity, so it is not placed under `contracts/` as a Solidity contract. Its relevant source path was `bifrost/pkg/chainclients/ethereum/ethereum_block_scanner.go`.

## Vulnerability Classification

The incident is best classified as a cross-component validation and trust-boundary failure. The Router emitted events and exposed functions that could be reached through contracts, while the Bifrost assigned meaning to those events and transaction fields without sufficiently proving that the observed value represented a genuine user deposit or genuine vault action.

The July 9 whitehat incident also exposed an ERC-777 reentrancy issue in the Router. That issue is documented separately in `writeups/erc777-reentrancy.md` because it is a distinct vulnerability from the later $8 million exploit.

## Repository Structure

`contracts/THORChain_RouterV2_vulnerable.sol` contains the exploit-relevant Solidity implementation and is intentionally focused on the vulnerable Router surface rather than pretending to reproduce unrelated infrastructure.

`summary.md` provides the detailed incident background and root cause. `exploit.md` explains the two July attack paths and the Router/Bifrost trust boundary. `fix.md` explains the changes required to prevent the same class of problem. 


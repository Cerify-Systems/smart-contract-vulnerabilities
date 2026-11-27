# Summary

Deus Finance was a decentralized finance protocol operating on Fantom. One of its lending systems allowed users to deposit collateral and borrow DEI. Like other collateralized lending systems, the protocol needed a reliable valuation of collateral to determine how much could be borrowed and whether a position remained solvent.

The March 15, 2022 incident exposed a fundamental weakness in that valuation process. The lending system relied on an Oracle whose pricing logic was derived from the USDC/DEI liquidity pool. Because the pool's reserves could be changed within a transaction, the reported price could be pushed far away from the normal market price using temporary liquidity obtained through flash loans.

The important contract on the lending side was `DeiLenderSolidex`. Its liquidation and solvency checks depended on an oracle price. Contemporary incident analysis identifies `liquidate()` as calling `isSolvent()`, which in turn obtained the collateral price through `Oracle.getPrice()`. This created the critical dependency: an attacker did not need to break the lending contract's access control or directly modify its storage. Instead, the attacker manipulated the information the lending contract trusted.

The oracle's on-chain pricing calculation used balances of the DEI and USDC tokens in the relevant pair and the pair's total supply. This made the oracle sensitive to the current reserve state. A flash loan could provide enough capital to temporarily move the USDC/DEI market. While the manipulated state existed, the oracle could return an inflated or otherwise incorrect value for the collateral. The attacker could then interact with the lending contract while the protocol believed the manipulated valuation.

The March 15 attack primarily resulted in malicious liquidation of positions. Contemporary reporting states that the attacker used flash loans to manipulate the price oracle for the USDC/DEI pair, causing lending positions to become insolvent and enabling the attacker to obtain roughly $3 million in value.

The important lesson is that an oracle is part of the security boundary of a lending protocol. A mathematically correct calculation is not necessarily a secure oracle calculation. If the input market can be moved cheaply within one transaction, the resulting price should not be used directly for high-value collateral decisions.

This incident is also particularly useful as a smart-contract security case study because the vulnerable behavior is distributed across two components. `DeiLenderSolidex` contains the financial decision that trusts the price, while `Oracle` contains the mechanism that derives the price from a manipulable DEX state. Reviewing only the lending contract without reviewing its oracle dependency would miss the actual attack surface.

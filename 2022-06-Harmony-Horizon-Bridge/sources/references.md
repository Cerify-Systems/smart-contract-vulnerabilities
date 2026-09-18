# References — Harmony Horizon Bridge Exploit

## Official / Primary Sources

### 1. Harmony — Summary of the Horizon Bridge Incident

https://talk.harmony.one/t/summary-of-the-horizon-bridge-incident/20990

This is Harmony's incident summary describing the timeline, compromised validator keys, affected assets, infrastructure compromise, and the investigation.

---

### 2. FBI — Harmony Horizon Bridge Currency Theft

https://www.fbi.gov/news/press-releases/fbi-confirms-lazarus-group-cyber-actors-responsible-for-harmonys-horizon-bridge-currency-theft

The FBI confirmed that Lazarus Group / APT38 was responsible for the theft of approximately $100 million from Harmony's Horizon Bridge.

---

## Smart Contract Sources

### 3. MultiSigWallet — Ethereum Mainnet

Address:

0x715CdDa5e9Ad30A0cEd14940F9997EE611496De6

Verified contract:

https://etherscan.io/address/0x715cdda5e9ad30a0ced14940f9997ee611496de6#code

Relevant functions include:

- submitTransaction()
- confirmTransaction()
- executeTransaction()
- isConfirmed()
- required()
- getOwners()

---

### 4. ERC20EthManager — Ethereum Mainnet

Address:

0x2dCCDB493827E15a5dC8f8b72147E6c4A5620857

Verified contract:

https://etherscan.io/address/0x2dccdb493827e15a5dc8f8b72147e6c4a5620857#code

Relevant functionality includes:

- unlockToken()
- Bridge wallet authorization
- ERC-20 asset management

---

## Technical Analysis

### 5. Halborn — Explained: The Harmony Horizon Bridge Hack

https://www.halborn.com/blog/post/explained-the-harmony-horizon-bridge-hack

Provides a technical explanation of the two-key compromise and the bridge's multisignature security model.

---

### 6. DeFiHackLabs — Harmony Multisig Exploit PoC

https://github.com/SunWeb3Sec/DeFiHackLabs/blob/main/src/test/2022-06/Harmony_multisig_exp.sol

Contains a reproduction of the attack using the deployed Harmony multisig and demonstrates the two-signature execution path.

---

### 7. Harmony — Horizon Bridge / Trustless Ethereum Bridge

https://open.harmony.one/strategy-roadmap/launch-dates-weekly-updates/trustless-ethereum-bridge

Documents Harmony's work toward a trustless Ethereum bridge following the earlier bridge architecture.

---

## Incident Impact

### 8. Harmony — Reimbursement Proposal

https://talk.harmony.one/t/reimbursement-proposal-horizon-incident/20665

Harmony reported the incident as involving approximately:

- $99.34 million in digital assets
- Approximately 65,000 wallets
- 14 different asset types

---

## Classification

Incident:

Harmony Horizon Bridge Exploit

Date:

June 23, 2022

Loss:

Approximately $100 million

Primary Cause:

Compromise of validator private keys

Security Weakness:

Insufficient multisignature authorization threshold

Attack Category:

Cross-chain bridge / Multisig / Key compromise
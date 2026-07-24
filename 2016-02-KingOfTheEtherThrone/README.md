# King of the Ether Throne (2016)

## Overview

King of the Ether Throne was one of the earliest Ethereum-based games where users competed to become the "King" by paying more Ether than the current ruler. Whenever a new player claimed the throne, the previous king was supposed to receive compensation automatically.

In 2016, the contract suffered from a payment handling vulnerability after a player became king using a contract wallet whose fallback function could not receive Ether using the contract's transfer mechanism. This incident became one of the earliest lessons on securely handling Ether transfers in smart contracts.

---

## Background

The game followed a simple mechanism:

1. A player pays the current claim price.
2. The player becomes the new king.
3. The previous king receives compensation.
4. The claim price increases for the next challenger.

The vulnerability arose because the contract assumed that every compensation payment would succeed.

---

## Root Cause

The original deployed contract attempted to immediately send Ether to the previous king whenever a new king claimed the throne.

If the recipient was a smart contract with a fallback function that rejected the transfer or required more gas than provided, the payment failed.

As a result:

- The previous king did not receive compensation.
- Ether could become inaccessible.
- The payment mechanism behaved unexpectedly when interacting with contract accounts.

The incident highlighted the risks of making external Ether transfers during critical contract execution.

---

## Impact

- Compensation payments could fail.
- Previous monarchs might not immediately receive their Ether.
- The incident demonstrated that smart contracts cannot assume all recipients can accept Ether.
- It established the importance of designing contracts that remain functional even when external calls fail.

---

## Official Fix

The official source code in this repository is **Version 1.0.0 (31 July 2016)**, which already contains the fix introduced after the incident.

Instead of permanently failing when compensation cannot be delivered, the contract:

- Checks whether the Ether transfer succeeds.
- If the transfer fails, records the compensation inside the contract.
- Allows the previous monarch to withdraw the funds later using a withdrawal function.

This prevents the game from becoming unusable because of a failed payment.

---

## Modern Best Practices

Modern Solidity contracts should avoid automatically pushing Ether to users.

Recommended practices include:

- Use the **Pull Payment (Withdrawal) Pattern** instead of immediate transfers.
- Always check the success of external calls.
- Keep contract state updates independent from Ether transfers.
- Assume that recipient contracts may reject Ether or consume unexpected gas.
- Use `call` carefully together with proper error handling instead of relying on older transfer mechanisms.

---

## Repository Contents

```
2016-02-King-of-the-Ether-Throne/
│
├── contracts/
│   └── KingOfTheEtherThrone.sol
│
├── sources/
│
└── README.md
```

---

## Notes

The contract included in the `contracts` directory is the official source released by the project author after the incident. It contains the mitigation for the payment failure vulnerability and serves as the reference implementation for understanding both the original issue and its resolution.

---

## Lessons Learned

- Never assume an Ether transfer will always succeed.
- External calls should always be handled safely.
- Use pull payments instead of push payments whenever possible.
- Smart contracts should continue operating correctly even if a recipient cannot immediately receive Ether.
- Proper error handling is essential for secure payment logic.

---

## References

- Official King of the Ether Throne source repository
- Official King of the Ether Throne postmortem
- Solidity Security Considerations
- SWC-104: Unchecked Call Return Value
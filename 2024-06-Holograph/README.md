# Holograph Protocol Infinite Mint Exploit (June 2024)

## Overview

On June 13, 2024, Holograph Protocol suffered a critical security incident that resulted in the unauthorized minting of 1 billion HLG tokens.

The exploit caused significant token inflation and led to an immediate collapse in HLG market value.

Estimated impact exceeded $14 million.

---

## Incident Details

| Item | Value |
|--------|--------|
| Protocol | Holograph |
| Date | June 13, 2024 |
| Vulnerability Type | Access Control Failure |
| Impact | Infinite Mint |
| Tokens Minted | 1,000,000,000 HLG |
| Estimated Loss | ~$14.4 Million |

---

## Vulnerability Summary

The attacker abused privileged execution permissions within Holograph's infrastructure.

By leveraging an authorized execution path, the attacker was able to invoke token minting functionality and generate 1 billion HLG tokens.

The attack did not rely on:

- Reentrancy
- Integer overflow
- Flash loans
- Oracle manipulation

Instead, it resulted from excessive trust in privileged actors and insufficient authorization controls around mint execution.

---

## Attack Flow

1. Attacker gained access to a trusted execution path.
2. Authorization checks were bypassed through privileged permissions.
3. Mint functionality was executed.
4. 1 billion HLG tokens were created.
5. Tokens were bridged across networks.
6. Tokens were sold on the market.
7. HLG price collapsed.

---

## Contract Selected For Analysis

### HolographERC20.sol

This contract is the primary token implementation responsible for:

- Token supply management
- Mint operations
- Burn operations
- ERC20 functionality

Although the authorization issue originated elsewhere, the exploit's impact materialized through token minting.

For this reason, HolographERC20.sol is the most relevant contract for understanding:

- How supply inflation occurred
- Why 1 billion HLG could be created
- How unauthorized minting affected the protocol

---

## Why This Contract Matters

The exploit can be summarized as:

Trusted Permission
        ↓
Mint Function Access
        ↓
1 Billion HLG Minted
        ↓
Supply Inflation
        ↓
Market Collapse

HolographERC20.sol represents the final destination of the exploit and the location where the protocol's economic damage became visible.

---

## Security Lessons

### Principle of Least Privilege

No privileged role should possess unrestricted mint authority.

### Authorization vs Authentication

Being an authorized actor should not automatically permit unlimited minting.

### Defense in Depth

Critical functions such as minting should require additional verification.

### Insider Threat Protection

Security designs should assume trusted actors can become malicious.

---

## Key Takeaways

- Infinite mint attacks are often authorization failures.
- Trusted infrastructure can become a single point of failure.
- Access control is one of the most critical components of blockchain security.
- Economic damage often occurs in token contracts even when the root cause exists elsewhere.
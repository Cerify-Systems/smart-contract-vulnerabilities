# 2018-04 — SmartMesh (SMT) — "proxyOverflow" (part of the BatchOverflow family)

 **Protocol/Token** -SmartMesh (SMT), ERC-20 token on Ethereum 
 **Date**- April 24–25, 2018 
 **Chain**- Ethereum 
 **Impact**- Attacker minted an equivalent of over $5 octodecillion (5×10^57) worth of counterfeit SMT via integer overflow; exchanges (Huobi, OKEx, Poloniex, HitBTC, Changelly, etc.) halted ERC-20 deposits/withdrawals across the board in response 
**Root cause**- Classic unchecked integer overflow (pre-Solidity-0.8 / pre-SafeMath) in the `transferProxy()` function's fee+value arithmetic |


## Naming note

This incident is commonly grouped under the informal "**BatchOverflow**" umbrella because it
surfaced in the same week, was found by the same researchers (PeckShield), and shares the
same root cause class (unchecked 256-bit integer overflow) as the original **batchOverflow**
bug in BeautyChain's (BEC) `batchTransfer()`. SmartMesh's specific vulnerable function was
**not** `batchTransfer()` it was `transferProxy()`, a delegated/meta-transaction style
transfer function so PeckShield tagged the SMT-specific variant **proxyOverflow**
(CVE-2018-10376). Both bugs are included here for completeness since your other incident
folders reference "BatchOverflow" as the family name.

## Folder layout

```
2018-04-SmartMesh/
├── README.md          (this file)
├── exploit.md          Step-by-step breakdown of the transferProxy overflow
├── fix.md               How it was fixed / how to prevent this class of bug
├── summary.md          One-page executive summary
├── contracts/
│   └── SMT.sol           SmartMesh ERC-20 token, including the vulnerable
│                          transferProxy() function (function body reproduced from the
│                          verified Etherscan source; surrounding contract reconstructed)
└── writeups/
    └── sources.md       Links to primary post-mortems used to build this folder
```

## One-line summary

`transferProxy(_from, _to, _value, _feeSmt, _v, _r, _s)` let a relayer submit a signed,
delegated transfer on behalf of a token holder in exchange for a fee. Its balance check was
`if (balances[_from] < _feeSmt + _value) revert();` but `_feeSmt` and `_value` are
attacker-controlled `uint256`s with **no overflow protection**. By choosing values that sum
to exactly `2^256` (e.g. `_value = 0x8fff...ffff` and `_feeSmt = 0x7000...0001`), the sum
wraps around to `0`, so the check `balances[_from] < 0` is always false and the transfer
proceeds — crediting the attacker-chosen `_to` and `msg.sender` addresses with an enormous
amount of tokens neither the sender nor the contract ever held.

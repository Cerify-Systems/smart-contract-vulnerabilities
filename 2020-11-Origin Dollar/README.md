# Origin Dollar (OUSD) Reentrancy Incident — November 2020

## Overview

| | |
|---|---|
| **Protocol** | Origin Protocol — Origin Dollar (OUSD) |
| **Vulnerability type** | Reentrancy (missing asset validation + insufficient reentrancy protection) |
| **Date of attack** | November 17, 2020, 00:47:19 UTC |
| **Funds lost** | ~$7.7M (11,809 ETH + 2,249,821 DAI) |
| **Vulnerable contract** | `VaultCore.sol` |
| **Vulnerable function** | `mintMultiple()` |
| **Root cause** | Missing per-asset support validation + reentrancy exposure in the mint/rebase flow |
| **Status** | Fixed, users fully compensated, contracts relaunched |

---

## Description

OUSD is a rebasing stablecoin that maintains its peg by holding a basket of other stablecoins (DAI, USDC, USDT) as collateral in a `Vault` contract. Users deposit these stablecoins and receive OUSD in return via the Vault's `mint()` (single-asset) or `mintMultiple()` (multi-asset) functions.

On November 17, 2020 — less than two months after OUSD's launch — an attacker exploited a flaw in `mintMultiple()` that allowed a **fake, attacker-controlled ERC-20-like contract** to be passed in as if it were a legitimate supported stablecoin. This let the attacker hijack control flow mid-transaction (reentrancy) and manipulate the Vault's rebase/mint accounting, artificially inflating the total supply of OUSD. The attacker then redeemed the inflated OUSD for real collateral, draining the Vault.

---

## Why This Vulnerability Happened

Two compounding issues in the pre-attack version of `VaultCore.sol` made the exploit possible:

1. **Missing asset validation in `mintMultiple()`**
   Unlike the single-asset `mint()` function, `mintMultiple()` did not properly validate — for each asset in the array — that the token being deposited was actually on the Vault's supported asset list. This meant an attacker could supply an arbitrary contract address in place of a real stablecoin.

2. **Insufficient reentrancy protection on the mint/rebase path**
   Because the "asset" was untrusted, the Vault ended up calling `transferFrom()` on the attacker's malicious contract. That contract implemented a hidden hook inside its `transferFrom()`, which re-entered the Vault **before** the first mint's OUSD-supply accounting had been finalized. This let the attacker trigger an additional `rebase()` mid-transaction, inflating `totalSupply()` based on collateral that had been transferred in but not yet properly accounted for — and then complete the original mint on top of that inflated state.

In short: **an unchecked external call (to an untrusted "asset" contract) combined with a mint flow that wasn't atomic against reentrancy** allowed the attacker to get the Vault to mint far more OUSD than the actual collateral it received.

This class of bug — "asset not validated + reentrancy into rebase/mint logic" — was later cataloged as a canonical audit finding:

> *"Missing checks and no reentrancy prevention allow untrusted contracts to be called from `mintMultiple`. This could be used by an attacker to drain the contracts."*
> — [Secureum Audit Findings 101](https://github.com/x676f64/secureum-mind_map/blob/master/content/7.%20Audit%20Findings%20101/Reentrancy%20and%20untrusted%20contract%20call%20in%20%60mintMultiple%60.md)

---

## Attack Flow

```
1. Attacker takes a flash loan (~70,000 ETH from dYdX)
   └─ Swaps portions into ~7.85M USDT and ~20.99M DAI via Uniswap

2. Attacker deploys a malicious "FakeToken" contract
   └─ Implements transferFrom() with a hidden reentrancy hook

3. Attacker calls VaultCore.mint() with ~7.5M USDT (legitimate)
   └─ Real OUSD minted, no issue yet

4. Attacker calls VaultCore.mintMultiple() with:
      - 20.5M DAI (real)
      - FakeToken (attacker-controlled, disguised as a "supported" asset)
   └─ mintMultiple() fails to validate that FakeToken is actually supported
   └─ Vault calls FakeToken.transferFrom(attacker, vault, amount)

5. FakeToken.transferFrom() hook fires
   └─ Re-enters the Vault mid-execution of mintMultiple()
   └─ Triggers a rebase() BEFORE the pending mint's accounting settles
   └─ totalSupply() is inflated using the DAI already transferred in,
      without yet accounting for the OUSD about to be minted for it

6. Execution returns to the original mintMultiple() call
   └─ The original mint (backed by the same 20.5M DAI) completes NORMALLY
   └─ Net effect: OUSD supply is inflated ~2x relative to real backing
   └─ Every OUSD holder's balance rebases upward, including the attacker's

7. Attacker redeems inflated OUSD for real collateral
   └─ 7 redeem transactions drain ETH/DAI/USDT from the Vault
   └─ Swaps proceeds (OUSD → USDT/USDC → ETH) via Uniswap & SushiSwap
   └─ Launders portion of funds through Tornado Cash and renBTC
```

**Attack transaction:** `0xe1c7...8401`
**Attacker's exploit deployment:** `0xb77f7bbac3264ae7abc8aedf2ec5f4e7ca079f83` (contract deployed Nov-17-2020 12:40:56 AM UTC — ~7 minutes before the attack)

---

## Contract & Function Reference

### Repository
- **Main repo:** https://github.com/OriginProtocol/origin-dollar

### The exploited contract
`contracts/contracts/vault/VaultCore.sol` (Solidity `0.5.11`, original single-strategy multi-asset Vault design used at launch).

A later, **already-patched** version of this exact file is viewable here:
- https://github.com/OriginProtocol/origin-dollar/blob/325bfa4e5a85d348caad36875aceed2ec0f9e55c/contracts/contracts/vault/VaultCore.sol


### The faulty function (as it existed pre-fix, reconstructed from post-mortems and audit findings)
```solidity
function mintMultiple(
    address[] calldata _assets,
    uint256[] calldata _amounts,
    uint256 _minimumOusdAmount
) external whenNotCapitalPaused /* insufficient reentrancy protection */ {
    // ⚠ Missing: require(assets[_assets[j]].isSupported, "Asset is not supported");
    //   for each asset in the loop — this check was added AFTER the hack.
    ...
    for (uint256 i = 0; i < _assets.length; i++) {
        IERC20 asset = IERC20(_assets[i]);
        asset.safeTransferFrom(msg.sender, address(this), _amounts[i]); // ⚠ external call to
                                                                          //    an unvalidated,
                                                                          //    attacker-controlled
                                                                          //    "asset"
    }
    ...
}
```

### The Vault contract deployed on-chain at the time of the attack
- **Address:** `0x226de75867B2f785BA19600e2a7e6eFccD57157B` ("Origin Dollar: Vault Core 2")
- **Etherscan:** https://etherscan.io/address/0x226de75867B2f785BA19600e2a7e6eFccD57157B
  > Note: Etherscan serves the re-verified (patched) source for this address; it does not expose the original pre-fix bytecode/source directly.

### Related GitHub issue history
- [OIP-4 — Disallow mints from off-peg stablecoin (#1000)](https://github.com/OriginProtocol/origin-dollar/issues/1000) — a related hardening effort for the mint path.

---

## Loss Incurred & Impact

| Metric | Value |
|---|---|
| **Total loss** | ~$7.7M (approx. 11,809 ETH + 2,249,821 DAI) |
| **Origin team/founder/employee losses** | >$1M of the total (Origin and its founders/employees were depositors too) |
| **OUSD price impact** | Fell ~85% (from ~$1.00 to as low as ~$0.14–$0.86 depending on venue/timing) |
| **Immediate response** | Deposits disabled within hours; public post-mortem released |
| **User impact** | All OUSD holders affected by supply distortion; deposits/withdrawals frozen during investigation |
| **Broader DeFi context** | One of several reentrancy-based DeFi hacks in Nov 2020 (alongside Akropolis, 12 days earlier) — part of a wave of flash-loan-enabled reentrancy exploits that year |

Origin subsequently committed to, and executed, a **100% compensation plan** for all OUSD holders affected at the time of the exploit, funded by the team.

---

## The Fix

Following the incident, Origin rebuilt and hardened the Vault contracts before relaunching OUSD. Key changes included:

1. **Explicit asset validation inside `mintMultiple()`**
   Added a per-asset check inside the loop:
   ```solidity
   // In memoriam
   require(assets[_assets[j]].isSupported, "Asset is not supported");
   ```
   This ensures every single asset passed into a multi-asset mint call is verified against the Vault's actual supported-asset registry — closing the door on fake "stablecoin" contracts.

2. **Reentrancy guards (`nonReentrant`) applied consistently** across all state-changing, fund-moving entry points: `mint()`, `mintMultiple()`, `redeem()`, `redeemAll()`, `allocate()`, and `rebase()`.

3. **General security process improvements**, per Origin's own post-mortem:
   - Additional smart contract audits
   - Bug bounty program
   - Internal security review processes
   - More conservative rollout practices for new contract logic

Full detail: [*What We've Changed Since the OUSD Attack*](https://medium.com/originprotocol/what-weve-changed-since-the-ousd-attack-5894f2bd77cf) — Origin Protocol, Jan 2021.

The modern OUSD/OETH Vault codebase (`master` branch) continues this pattern — every user-facing mint/redeem/allocate/rebase function carries a `nonReentrant` modifier, and newer single-collateral vault variants (e.g., for OETH) sidestep the multi-asset validation problem entirely by only supporting one asset per vault instance.

---

## References

- [PeckShield — Origin Dollar Incident: Root Cause Analysis](https://blog.peckshield.com/2020/11/17/ousd/) (primary technical post-mortem, with annotated exploit flow)
- [Origin Protocol — Urgent: OUSD was hacked and there has been a loss of funds](https://medium.com/originprotocol/urgent-ousd-has-hacked-and-there-has-been-a-loss-of-funds-7b8c4a7d534c) (official incident report)
- [Origin Protocol — What We've Changed Since the OUSD Attack](https://medium.com/originprotocol/what-weve-changed-since-the-ousd-attack-5894f2bd77cf) (official post-mortem & remediation)
- [CoinDesk — Origin Protocol Loses $7M in Latest DeFi Attack](https://www.coindesk.com/markets/2020/11/17/origin-protocol-loses-7m-in-latest-defi-attack)
- [The Block — DeFi protocol Origin gets attacked, loses $7 million](https://www.theblock.co/post/84804/defi-protocol-origin-attack-7-million-lost)
- [The Daily Swig — Origin Dollar cryptocurrency hacked to the tune of $7m](https://portswigger.net/daily-swig/origin-dollar-cryptocurrency-hacked-to-the-tune-of-7m-less-than-two-months-after-launch)
- [Secureum — Audit Findings 101: Reentrancy and untrusted contract call in `mintMultiple`](https://github.com/x676f64/secureum-mind_map/blob/master/content/7.%20Audit%20Findings%20101/Reentrancy%20and%20untrusted%20contract%20call%20in%20%60mintMultiple%60.md)
- [Slither Trophies — documented list of vulnerabilities/incidents (incl. OUSD, Nov 2020)](https://github.com/crytic/slither/blob/master/trophies.md)
- [OriginProtocol/origin-dollar — GitHub repository](https://github.com/OriginProtocol/origin-dollar)
- [VaultCore.sol — post-fix historical version](https://github.com/OriginProtocol/origin-dollar/blob/325bfa4e5a85d348caad36875aceed2ec0f9e55c/contracts/contracts/vault/VaultCore.sol)
- [Vault contract on Etherscan](https://etherscan.io/address/0x226de75867B2f785BA19600e2a7e6eFccD57157B)


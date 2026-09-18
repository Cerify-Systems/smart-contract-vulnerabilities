# Drips Network — `DaiDripsHub` Arithmetic/Type-Conversion Exploit

## Summary

| | |
|---|---|
| **Protocol** | Drips Network (legacy V1 — `DaiDripsHub`) |
| **Date of Exploit** | July 14, 2026 |
| **Vulnerability Class** | Arithmetic error — unchecked `uint128 → int128` type conversion |
| **Root Cause Function** | `_give()` (calling `_transfer()` with an unvalidated signed cast) |
| **Loss** | ~24,882.99 DAI (entire reserve balance) |
| **Reported By** | SlowMist / Verichains |

Drips Network is an EVM protocol for streaming and splitting ERC-20 token payments, originally built by the Radicle/Radworks ecosystem. On July 14, 2026, a **legacy `DaiDripsHub` deployment** on Ethereum was drained of its entire DAI reserve through a single crafted transaction that exploited an unsafe signed/unsigned integer conversion — not an access-control bypass, not an oracle manipulation, but a plain arithmetic type-casting flaw.

---

## 🧩 Description of the Vulnerability

The vulnerable contract exposed a public function:

```solidity
function give(address receiver, uint128 amt) external;
```

Its intended behavior: the caller "gives" `amt` DAI to `receiver`, who can immediately collect it. Internally, this called a private helper:

```solidity
function _give(address user, address receiver, uint128 amt) internal {
    _collectable[receiver] += amt;
    _transfer(user, -int128(amt));   // <-- unchecked, unsafe cast
}
```

The negative sign passed into `_transfer()` was meant to encode **direction**:
- Negative → pull funds **from the user into the reserve** (a deposit)
- Positive → pull funds **from the reserve to the user** (a withdrawal)

```solidity
function _transfer(address user, int128 amt) internal {
    if (amt > 0) {
        // withdraw from reserve, send to user
    } else if (amt < 0) {
        // deposit from user into reserve
    }
}
```

The flaw: `amt` is a fully **user-controlled `uint128`**, and the code casts it directly to `int128` and negates it — assuming `-int128(amt)` is *always* negative. That assumption only holds when:

```
amt <= type(int128).max
```

**No such bounds check existed.** If a caller supplies a `uint128` value greater than `type(int128).max` (i.e., with its high bit set), the explicit cast reinterprets the same 128-bit pattern as a **negative** signed number, and the subsequent unary negation (`-`) flips it back to **positive** — silently reversing the intended transfer direction.

---

## ⚙️ Why This Happened (Root Cause)

1. **Direction encoded implicitly via sign**, instead of using an explicit deposit/withdraw parameter or separate function paths.
2. **No range validation** on `amt` before the `uint128 → int128` cast.
3. **False sense of safety from Solidity 0.8's checked arithmetic.** Solidity 0.8+ reverts on arithmetic *overflow/underflow*, but this protection does **not** apply to explicit type casts — `int128(amt)` is a deliberate reinterpretation of bits, not an arithmetic operation, so it compiles and executes without any revert even when it silently flips sign.
4. **Trust boundary collapse.** The DAI reserve contract correctly restricted withdrawals to its authorized hub and checked its own internal balance — but those checks were useless here because the *hub itself* (the trusted, authorized caller) was tricked into requesting exactly the full reserve balance.

---

## 💥 Attack Flow

Let `B` = the DAI reserve's exact balance, in the smallest unit:

```
B = 24,882,995,421,947,667,857,715
```

The attacker computed:

```
A = 2^128 − B
  = 340,282,366,920,938,438,580,379,185,484,100,353,741
```

`A` is a valid `uint128` value, but it exceeds `type(int128).max`, so when cast:

```
int128(A)   = A − 2^128 = −B
-int128(A)  = B
```

### Step-by-step:

1. The attacker's contract called `give(receiver, A)` on the hub, where `A = 2^128 − B`.
2. `_give()` credited the chosen receiver's `collectable` balance with the huge unsigned value `A` (harmless bookkeeping, since it's just a mapping increment).
3. `int128(A)` evaluated to `−B`; the leading unary minus flipped it to `+B`.
4. `_transfer()` received a **positive** `amt` and took the **withdrawal branch**, calling `erc20Reserve.withdraw()` for the full reserve balance `B`.
5. The hub sent the withdrawn DAI to the attack contract, which forwarded it to the attacker's EOA.

The entire attack executed in **a single transaction**.

---

## 🏦 Real-World Contracts Involved

| Role | Address |
|---|---|
| Attacker EOA | [`0x84dA7a5e2315Eb798f04B75554AeB15047269CCE`](https://etherscan.io/address/0x84da7a5e2315eb798f04b75554aeb15047269cce) |
| Attack Contract | [`0x00c64B5a926ba1fceC30EfaD88C344c619F54F12`](https://etherscan.io/address/0x00c64b5a926ba1fcec30efad88c344c619f54f12) |
| Vulnerable Hub Proxy (`DaiDripsHub`) | [`0x73043143e0a6418cc45d82d4505b096b802fd365`](https://etherscan.io/address/0x73043143e0a6418cc45d82d4505b096b802fd365) |
| Implementation at Attack Block | [`0x8d321e80487356c846f34456d31ce761776ef697`](https://etherscan.io/address/0x8d321e80487356c846f34456d31ce761776ef697#code) |
| DAI Reserve Contract | [`0xf9bbb2df44cfe46e501cf91c99b2f8fef9d9d44a`](https://etherscan.io/address/0xf9bbb2df44cfe46e501cf91c99b2f8fef9d9d44a#code) |
| Exploit Transaction | [`0xc38a6e2259a85ced94238a0b0a49697992f2a6b8140c28f3fd2343d3d8434130`](https://etherscan.io/tx/0xc38a6e2259a85ced94238a0b0a49697992f2a6b8140c28f3fd2343d3d8434130) |

> **Note:** This is a **legacy V1** deployment. Drips Network's current, actively maintained codebase (`drips-network/contracts`) is the V2 protocol, which does not contain this `DaiDripsHub` implementation on its `main`/v2 branches. The affected code originated from the earlier `radicle-dev/drips-contracts` repository (v1 lineage). Because the exact historical file/commit could not be conclusively verified via public search, the verified bytecode/source for the vulnerable implementation is best referenced directly on Etherscan (link above) rather than a guessed GitHub path.

### Function Involved

```solidity
// Public entry point
function give(address receiver, uint128 amt) external;

// Internal — root cause
function _give(address user, address receiver, uint128 amt) internal {
    _collectable[receiver] += amt;
    _transfer(user, -int128(amt));   // unchecked uint128 -> int128 cast
}

// Internal — misled by _give(), but not itself the root cause
function _transfer(address user, int128 amt) internal {
    if (amt > 0) {
        // withdrawal path
    } else if (amt < 0) {
        // deposit path
    }
}
```

| Function | Role |
|---|---|
| `give()` | Public entry point exploited by the attacker |
| `_give()` | **Root cause** — unchecked signed cast with no upper-bound validation |
| `_transfer()` | Trigger point — correct logic, but deceived by corrupted input |

### GitHub References

- Drips Network (current V2) organization: https://github.com/drips-network
- V2 smart contracts repository: https://github.com/drips-network/contracts
- Legacy origin (Radicle Funding / V1 lineage): https://github.com/radicle-dev/drips-contracts
- Drips audit reports (referenced in bug bounty program):
  - https://docs.drips.network/assets/files/Spearbit_Drips_Network_Security_Review-d5cda225c36d4c2f1185e154431812b5.pdf
  - https://docs.drips.network/assets/files/Drips_Audit_Report-c2efbc01f0ce28c8847226339d63c3a7.pdf
  - https://docs.drips.network/assets/files/Certora_Radicle_Drips_Report-a557b047cd7806033d47cfcba1ce334e.pdf
- Bug bounty program (Immunefi): https://immunefi.com/bug-bounty/drips/information/

---

## 📉 Loss Incurred & Impact

- **Amount lost:** 24,882.995421947667857715 DAI — the **entire balance** of the DAI reserve at the time of the attack.
- **Scope of impact:** Limited to the legacy V1 `DaiDripsHub` deployment; Drips Network's current V2 protocol architecture was not affected by this specific flaw.
- **Trust/reputational impact:** Raised renewed scrutiny of legacy DeFi streaming contracts still holding user funds, and served as a reminder that "audited" or long-deployed contracts can still carry unaddressed type-safety issues, especially around sign-based direction encoding.
- **Operational impact:** Highlighted the need for a protocol-wide review/upgrade of any remaining legacy hub deployments still active on mainnet.

---

## 🛠️ The Fix

The recommended and generally applicable remediation is two-fold:

1. **Bounds-check before casting.** Before converting a `uint128` (or any unsigned type) to a signed type, explicitly validate:
   ```solidity
   require(amt <= uint128(type(int128).max), "amount too large");
   ```
   or use a checked-cast helper (e.g., OpenZeppelin's `SafeCast` library, which reverts on overflow during signed/unsigned conversions).

2. **Stop encoding transfer direction via the sign of a user-controlled value.** Instead:
   - Use two explicit functions/paths (`_deposit()` and `_withdraw()`), or
   - Pass an explicit `bool isWithdrawal` flag / enum alongside an always-unsigned magnitude.

   This removes any ambiguity or reliance on bit-level reinterpretation for a decision that has real financial consequences.

Solidity 0.8's built-in checked arithmetic protects against overflow/underflow in **arithmetic operations** (`+`, `-`, `*`, etc.), but it does **not** protect against unsafe **explicit type conversions** — that safety must be added manually or via a vetted library.

---

## 📚 Lessons Learned

1. **Checked arithmetic ≠ checked casting.** Solidity 0.8+ reverting on overflow gives a false sense of blanket safety; explicit type conversions (`int128(x)`, `uint256(y)`, etc.) are a completely separate risk surface and must be validated independently.
2. **Never let a security-critical branch depend on the sign of a value derived from user input** without validating the input's range first. Sign-based direction encoding is elegant but fragile — one uncontrolled input at the wrong scale silently reverses intended behavior.
3. **Authorization ≠ correctness.** The DAI reserve's access control (only the hub could call `withdraw()`) worked exactly as designed — the hub *was* authorized. The bug lived one layer up, in how the hub decided *what* to request, proving that access control alone cannot compensate for faulty internal logic.
4. **Legacy contracts remain live risk.** Even when a protocol has moved on to a newer, better-audited version (V2), older deployments left running in production continue to carry the entire blast radius of their original code.
5. **Prefer explicit over implicit.** Whenever a contract must express "direction," "mode," or "sign" as part of its logic, an explicit flag or separate function is safer and more auditable than inferring intent from a numeric sign or bit pattern.
6. **Audits are a snapshot, not a guarantee.** Drips Network had prior audit reports on file (Spearbit, Certora, and others) — a reminder that audits reduce risk but do not eliminate it, especially for code paths added or left unreviewed after the original audit scope.

---

## 🔗 References

- Verichains — ["Drips Network: When Giving Became Receiving"](https://blog.verichains.io/p/drips-network-when-giving-became) (July 24, 2026)
- SlowMist Hacked Database: https://hacked.slowmist.io/en/
- KuCoin News — "Drips Network loses 24,882.99 DAI due to integer conversion vulnerability": https://www.kucoin.com/news/flash/drips-network-loses-24-882-99-dai-due-to-integer-conversion-vulnerability
- Drips Network Bug Bounty Program (Immunefi): https://immunefi.com/bug-bounty/drips/information/
- Drips Network GitHub: https://github.com/drips-network


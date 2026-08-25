# Aurora DAO (AURA) / IDEX — `setOwner()` Access Control Vulnerability

**CVE:** CVE-2018-10705 (related: CVE-2018-10666 for the sibling IDXM token)

**Vulnerability class:** Broken Access Control / Improper Authorization

**Bug name (coined by PeckShield):** `ownerAnyone`

**Disclosed:** May 2018 (PeckShield advisory: May 3, 2018 · CVE published: May 9, 2018)

**Project:** Aurora DAO (AURA token), the ERC-20 token later swapped for the IDEX exchange token

**Severity:** Medium — no direct theft of funds, but enabled unauthorized contract takeover and Denial-of-Service

---

## 1. Summary

The `AURA` ERC-20 token contract (deployed by Aurora DAO, the team behind the **IDEX** decentralized exchange) inherited an `Owned` base contract that was meant to restrict privileged operations to a single `owner` address. However, the function responsible for **changing that owner** — `setOwner()` — was declared `public` with **no access-control modifier**. This meant *any* external account could call `setOwner()` and instantly become the contract owner, bypassing the entire permission model the contract was built on.

Because several sensitive functions (e.g. `unlockToken()`, `lockBalances()`) were correctly gated behind `onlyOwner`, taking over ownership gave an attacker the ability to invoke those functions too — most notably to **lock/freeze token balances**, resulting in a Denial-of-Service condition for legitimate holders and, potentially, for the IDEX exchange's token operations.

---

## 2. Why This Vulnerability Happened (Root Cause)

- The `Owned` contract correctly *defined* an `onlyOwner` modifier and correctly *applied* it to other sensitive functions.
- It **forgot to apply that same modifier to `setOwner()` itself** — the one function that governs who the owner is.
- In Solidity ^0.4.x, function visibility defaults matter: if visibility isn't explicitly restricted, functions can end up publicly callable. Combined with the missing modifier, this made `setOwner()` a fully open door.
- This is a classic **"privileged function without privilege check"** pattern — the developers protected the *use* of ownership but not the *assignment* of ownership.

In short: **authorization was enforced everywhere except at the single point that mattered most — the root of the trust chain.**

---

## 3. Attack Flow

1. **Reconnaissance:** Attacker inspects the verified AURA contract source on Etherscan and notices `setOwner(address _owner)` has no `onlyOwner` modifier and is publicly callable.
2. **Ownership takeover:** Attacker submits a transaction calling `setOwner(attackerAddress)` directly. Since there is no permission check, the call succeeds and `owner` is overwritten.
3. **Privilege abuse:** With ownership secured, the attacker can now call any `onlyOwner`-restricted function, such as:
   - `lockBalances()` — freezing token transfers for all holders (Denial-of-Service).
   - Other admin-only state variables that influence contract behavior.
4. **Impact realized:** Legitimate users of the AURA/IDEX ecosystem are unable to transfer or interact with their tokens while the contract is in this hijacked state.
5. **(Recovery path that existed):** Because `setOwner()` was equally open to everyone, the original team could — and reportedly did — reclaim ownership by simply calling `setOwner()` again with their own address, which is one reason the project classified it as "known but not critical."

```solidity
// Step 2 in practice — anyone could run this:
AURA.setOwner(0xCAFEBABE...);  // no onlyOwner check, transaction succeeds
```

---

## 4. Smart Contract & Faulty Function

**Contract:** `AURA` (Aurora DAO token), inheriting `SafeMath` and `Owned`
**Deployed address (Ethereum mainnet):** [`0xcdcfc0f66c522fd086a1b725ea3c0eeb9f9e8814`](https://etherscan.io/token/0xcdcfc0f66c522fd086a1b725ea3c0eeb9f9e8814#code)
**Solidity version:** `^0.4.19`

### Vulnerable code (`Owned` base contract)

```solidity
contract Owned {
    address public owner;

    function Owned() {
        owner = msg.sender;
    }

    // VULNERABLE: no onlyOwner modifier, publicly callable by anyone
    function setOwner(address _owner) returns (bool success) {
        owner = _owner;
        return true;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
}
```

Sensitive functions elsewhere in `AURA` *did* use the modifier correctly, e.g.:

```solidity
function lockBalances() onlyOwner returns (bool success) {
    locked = true;
    return true;
}

function unlockToken() onlyOwner returns (bool success) {
    locked = false;
    return true;
}
```

The inconsistency — modifier applied everywhere *except* `setOwner()` — is the entire root cause.

---

## 5. The Fix

The remediation is straightforward: apply the same `onlyOwner` access-control check to `setOwner()` that protects every other privileged function.

```solidity
// FIXED
function setOwner(address _owner) onlyOwner returns (bool success) {
    owner = _owner;
    return true;
}
```

General mitigations recommended by researchers covering this bug class:
- Always explicitly declare function visibility (`public`, `external`, `internal`, `private`) rather than relying on defaults.
- Any function that mutates privileged state (owner, admin, minter roles, etc.) must be guarded by an appropriate access-control modifier.
- Adopt battle-tested libraries (e.g. OpenZeppelin's `Ownable`) instead of hand-rolled ownership patterns, since these are audited and consistently enforce `onlyOwner` on `transferOwnership`.
- Run static analysis / linting (Slither, MythX, etc.) that flags unrestricted state-changing functions.

---

## 6. Loss Incurred & Impact

- **Direct financial loss:** None confirmed. Unlike reentrancy-style exploits (e.g. The DAO hack), this bug did **not** allow draining of user balances or theft of funds directly.
- **Realized impact:** The primary risk was **Denial-of-Service** — an attacker taking ownership and calling `lockBalances()` could freeze all token transfers for AURA/IDEX-related holders until ownership was reclaimed.
- **Severity assessment:** Aurora's team reportedly told researchers who reported it that it was a "known bug and not critical," reasoning that admins could always re-acquire ownership by calling `setOwner()` again, since it remained equally unrestricted for them too.
- **Reputational/trust impact:** Public disclosure (PeckShield's "ownerAnyone" advisory) highlighted a systemic pattern also found in the related IDEX Membership (IDXM) token contract, raising broader concern about access-control hygiene across the Aurora/IDEX contract suite.
- **EPSS (Exploit Prediction Scoring System):** ~0.33% probability of exploitation activity in a 30-day window, ~53rd percentile — reflecting low real-world exploitation likelihood despite the conceptual severity.

---

## 7. GitHub / Source References

- Etherscan verified source (primary contract reference): https://etherscan.io/token/0xcdcfc0f66c522fd086a1b725ea3c0eeb9f9e8814#code
- NVD — CVE-2018-10705 detail: https://nvd.nist.gov/vuln/detail/CVE-2018-10705
- CVE Details — CVE-2018-10705: https://www.cvedetails.com/cve/CVE-2018-10705/
- PeckShield original advisory ("ownerAnyone" bug): https://peckshield.com/2018/05/03/ownerAnyone/
- Related sibling vulnerability write-up (IDXM token, CVE-2018-10666): https://medium.com/@jonghyk.song/aurora-idex-membership-idxm-erc20-token-allows-attackers-to-acquire-contract-ownership-1ff426cee7c6

---

## 8. Timeline

| Date | Event |
|---|---|
| 2018-01-17 | AURA contract deployed / verified on Etherscan |
| 2018-05-03 | PeckShield publishes "ownerAnyone" vulnerability advisory |
| 2018-05-09 | CVE-2018-10705 officially published (MITRE/NVD) |
| 2019-10-03 | CVE record last updated |

---

## 9. Key Takeaway

> Access control must be verified at **every** state-changing entry point — especially the function that assigns access control itself. A single unprotected `setOwner()`/`transferOwnership()` function undermines every other permission check in the contract, no matter how correctly those other checks are implemented.
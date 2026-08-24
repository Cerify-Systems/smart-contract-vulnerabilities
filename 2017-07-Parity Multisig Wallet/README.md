# Parity Multisig Wallet Hack #1 — Broken Access Control on `initWallet`

**Date:** July 19, 2017
**Loss:** ~153,037 ETH (~$30M at the time; several hundred million USD at later ETH prices)
**Root cause:** Missing access control on an initialization function, combined with `delegatecall`-based proxy architecture

---

## 1. Description

Parity's multisig wallets used a **proxy + shared library** pattern. Instead of embedding wallet logic (ownership, transaction execution, daily limits) directly into every deployed wallet, Parity deployed **one shared library contract** (`WalletLibrary`), and each individual user wallet (`Wallet.sol`) was a thin proxy that forwarded any call it didn't understand to that library via `delegatecall`.

`delegatecall` executes the *library's* code but in the *context of the calling wallet's storage* — meaning any function in the library, when invoked through a wallet, can read and write that wallet's own storage (owners, balances, limits) as if the code were native to the wallet.

The library exposed an `initWallet` function that was meant to behave like a one-time constructor — setting the initial list of owners and required confirmations when a wallet was first created. It had **no protection preventing it from being called again after deployment**, and no restriction on *who* could call it.

Because every wallet's fallback function blindly forwarded calls to the library, `initWallet` was effectively a **public, callable-by-anyone function on every deployed wallet**, not just at creation time.

---

## 2. Attack Flow

1. **Reconnaissance** — The attacker identified that Parity multisig wallets forward unmatched calls to a shared `WalletLibrary` contract via `delegatecall`, and that the library's `initWallet` (and the `initMultiowned` it called) had no access control.
2. **Ownership hijack** — The attacker called `initWallet(_owners, _required, _daylimit)` directly on each target wallet's proxy address, supplying their own address as the sole/new owner.
3. **State overwrite via delegatecall** — Because the call was forwarded via `delegatecall`, `initMultiowned` executed against the *victim wallet's* storage, overwriting `m_owners`, `m_ownerIndex`, and `m_required` — making the attacker the wallet's owner, with no signatures from the legitimate owners required.
4. **Fund extraction** — Now recognized as the sole owner, the attacker called the wallet's normal `execute(address _to, uint _value, bytes _data)` function to transfer out the wallet's ETH balance.
5. **Repeated across targets** — This was executed against multiple wallets holding crowdsale funds, in rapid succession, before anyone could react.

### Why this vulnerability happened
- **No access control on a state-changing "constructor-like" function.** `initWallet`/`initMultiowned` lacked any modifier (e.g., "only once", "only owner", "only during creation") to prevent re-initialization.
- **Delegatecall proxy pattern amplified the blast radius.** Because logic lived in one shared library and was invoked via `delegatecall` from every wallet, a single missing check in the library became a vulnerability in *every* wallet that used it — not just one contract.
- **Constructor logic was extracted into a regular function.** In Solidity, true constructor code runs only once at deployment and is not part of the deployed bytecode. By moving that logic into an ordinary callable function (`initWallet`) so it could be reused as a library, Parity inadvertently made "constructor-only" logic permanently and repeatedly callable.
- **No formal audit.** Parity's own post-mortem noted the code went through internal/community review but not a formal security audit; a prior community warning about this exact initialization risk had been treated as a "convenience enhancement" rather than a critical fix.

---

## 3. Smart Contract & Function Reference

**Deployed vulnerable library contract (mainnet):**
`0x863DF6BFa4469f3ead0bE8f9F2AAE51c91A907b4` (Etherscan)

**Faulty functions (in `WalletLibrary` / `enhanced-wallet.sol`):**

```solidity
// constructor-like initializer — no access control
function initWallet(address[] _owners, uint _required, uint _daylimit) {
    initDaylimit(_daylimit);
    initMultiowned(_owners, _required);
}

// overwrites ownership state — callable by anyone via delegatecall
function initMultiowned(address[] _owners, uint _required) {
    m_numOwners = _owners.length + 1;
    m_owners[1] = uint(msg.sender);
    m_ownerIndex[uint(msg.sender)] = 1;
    for (uint i = 0; i < _owners.length; ++i) {
        m_owners[2 + i] = uint(_owners[i]);
        m_ownerIndex[uint(_owners[i])] = 2 + i;
    }
    m_required = _required;
}
```

**The delegatecall forwarding fallback (in `Wallet.sol`) that exposed the library's functions through every wallet:**

```solidity
function () payable {
    if (msg.value > 0) Deposit(msg.sender, msg.value);
    else if (msg.data.length > 0) _walletLibrary.delegatecall(msg.data);
}
```

---

## 4. References

- Vulnerable source (as linked from Parity's own wallet UI at the time):
  `https://github.com/paritytech/parity/blob/6b0e4f9098be6b841353e7c4f116aa86b7c2e3d6/js/src/contracts/snippets/enhanced-wallet.sol`
- Mirror (openethereum fork):
  `https://github.com/openethereum/parity-ethereum/blob/4d08e7b0aec46443bf26547b17d10cb302672835/js/src/contracts/snippets/enhanced-wallet.sol`
- Original GitHub issue discussion ("Anyone can kill your contract" — related follow-on incident):
  `https://github.com/paritytech/parity/issues/6995`
- Parity's official security post-mortem:
  `https://paritytech.io/blog/security-alert.html`
- White-hat rescue reconciliation (funds recovered and returned):
  `https://github.com/bokkypoobah/ParityMultisigRecoveryReconciliation`

---

## 5. Loss Incurred & Impact

| Victim | Approx. ETH Stolen |
|---|---|
| æternity | ~82,189 ETH |
| Swarm City | ~44,055 ETH |
| Edgeless Network | ~26,793 ETH |
| **Total** | **~153,037 ETH (~$30M at the time)** |

**Broader impact:**
- Confidence in Parity's wallet software and the broader "shared library / delegatecall proxy" pattern was severely shaken.
- A **white-hat group**, recognizing that hundreds of other wallets shared the identical flaw, raced to drain and safeguard those funds before a second attacker could — rescuing roughly **$180M more** and later returning it to the rightful owners.
- The affected ICOs (Edgeless Network, Swarm City, æternity) lost a significant portion of their crowdsale proceeds, disrupting their funding and roadmaps.
- The incident became one of the most cited case studies in smart contract security for **delegatecall risks** and **unprotected initializer functions** — a lesson that later directly informed patterns like OpenZeppelin's `Initializable`/`initializer` modifier for upgradeable contracts.
- It set the stage for a **second, related incident on November 6, 2017**, where the still-uninitialized shared library itself (never properly "claimed" after the July patch) was taken over and self-destructed by a user, freezing ~$280M across all dependent wallets permanently.

---

## 6. The Fix

**Immediate patch (deployed July 20, 2017):**
Parity added an `only_uninitialized` modifier to `initWallet`, restricting the initializer so it could only be called once — successfully closing the "re-initialize and steal ownership" attack path used on July 19.

```solidity
function initWallet(address[] _owners, uint _required, uint _daylimit)
    only_uninitialized
{
    initDaylimit(_daylimit);
    initMultiowned(_owners, _required);
}
```

**Further hardening (in later patched versions):**
`initMultiowned` and `initDaylimit` were also marked `internal`, removing them from the contract's public/external interface entirely so they could never again be invoked directly from outside — only through the guarded `initWallet` entry point.

**Lessons adopted industry-wide after this incident:**
- Never leave initializer functions unprotected — use explicit one-time-use guards (e.g., an `initialized` boolean checked and set atomically) rather than relying on constructors alone when using proxy/library patterns.
- Be cautious with `delegatecall`-based proxy architectures: any unprotected function in a shared library is exposed through *every* proxy that points to it — a single fix must be verified across the entire fleet of dependent contracts, and the library itself must be initialized/locked immediately upon deployment.
- Formal audits and adversarial review are essential for any contract managing pooled or third-party funds, especially for logic marketed as reusable infrastructure.
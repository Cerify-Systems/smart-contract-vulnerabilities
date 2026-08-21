# fix.md — What Actually Fixed This

## 1. The code-level fix
The core rule: **never keep using a `memory` copy of data after a function call that might have updated the real `storage` version.** Once you know a storage-modifying call has happened, re-read fresh values from storage (or restructure the code so calculations that depend on updated state happen after the update, using storage directly, not a memory snapshot taken beforehand).

**Vulnerable pattern (conceptual):**
```solidity
Pool memory pool = pools[_lpToken];   // snapshot taken
updatePool(_lpToken);                  // real storage updated, snapshot NOT updated
// ... later code still uses the stale `pool` memory variable
```

**Corrected pattern:**
```solidity
updatePool(_lpToken);                  // update storage FIRST
Pool storage pool = pools[_lpToken];   // then read a live reference, or re-fetch fresh values
// ... later code now uses up-to-date data
```

## 2. What the team actually did in response
- **Immediate:** revoked `Blacksmith`'s minting permissions by redirecting them to a dummy contract, stopping further exploitation within the same day.
- **Investigation:** worked directly with Yearn Finance partner Emiliano Bonassi, who independently reproduced the exploit in a test environment to confirm the exact mechanism.
- **Relaunch:** deployed a corrected version of the shield-mining contract and migrated the COVER token, with the storage/memory bug fixed in the new implementation.
- **Compensation:** the team worked on a compensation plan for affected liquidity providers, aided in part by the ETH that the white-hat actor ("Grap Finance") voluntarily returned after burning their own minted tokens.

## Why this incident matters as a teaching example
Unlike reentrancy (which is about *when* external calls hand back control), this bug is about **which copy of data your code is actually looking at**. It's a distinctly Solidity-flavored mistake, since the language requires developers to explicitly choose between `memory` and `storage` for every variable a choice most other programming languages don't force you to make explicitly. This makes it an excellent complementary example alongside a reentrancy incident: it shows a completely different root-cause category (data staleness vs. control-flow hijacking), reinforcing that "smart contract vulnerability" isn't just one pattern to watch for.

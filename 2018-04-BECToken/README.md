# BEC Token (BeautyChain) Vulnerability Issue — `batchOverflow` Integer Overflow

## Description of the Event

BeautyChain (BEC) was an ERC-20 token deployed on the Ethereum mainnet on 9 February 2018. Its contract, `BecToken`, extended the standard token logic with a custom convenience function, `batchTransfer`, that let a holder send the same amount of tokens to multiple recipients in a single transaction.

The function computed the total amount to debit from the sender as:

```
amount = cnt * _value
```

where `cnt` (number of recipients) and `_value` (amount per recipient) are both fully attacker-controlled inputs. This multiplication was performed using raw, unchecked 256-bit arithmetic rather than the `SafeMath` library the rest of the contract relied on. By choosing `_value = 2²⁵⁵` and `cnt = 2`, the product `2 × 2²⁵⁵ = 2²⁵⁶` silently wrapped around (overflowed) and evaluated to `0`.

Because `amount` evaluated to `0`, the balance-sufficiency check (`balances[msg.sender] >= amount`) passed trivially regardless of the sender's actual holdings, while the function still credited each of the two receivers the full `_value` (`2²⁵⁵` tokens) inside its loop. The result was the unauthorized creation of an astronomical number of BEC tokens, with no corresponding debit from any real balance. This bug class — an integer overflow in a multiplication that feeds directly into a security check — was named **"batchOverflow"** by the security firm that first flagged it, and the same flawed pattern was later found copy-pasted into a dozen other ERC-20 token contracts.

**Timeline of the exploit:**
- **22 April 2018, ~03:28 UTC** — Automated monitoring detected two abnormal BEC transfers, each moving `2²⁵⁵` tokens (a 256-bit value with 63 trailing zeros in hex), sent to two different attacker-controlled addresses directly from the BEC contract.
- The attacker had exploited `batchTransfer` to mint roughly **10⁵⁸ BEC tokens** in that single transaction — several orders of magnitude beyond BEC's entire legitimate total supply of 7,000,000,000 tokens.
- The attacker began dumping the newly created tokens onto exchanges, most notably OKEx.
- Within hours, exchanges (led by OKEx) **suspended BEC withdrawals and trading** to contain the damage.
- There was no way to "patch" the already-deployed, immutable contract — remediation was limited to exchange-level trading halts and, per some reports, a proposal to roll back/cancel transactions from that period.

**Loss incurred:**
The flood of illegitimate supply — effectively infinite tokens conjured from a single transaction — destroyed market confidence in BEC and **crashed its trading price to near zero** within the same day. All legitimate holders' token value was wiped out in practice, since the token became untradeable and worthless once exchanges halted markets and the supply was understood to be irreparably corrupted. Unlike hacks involving stolen ETH or stablecoins with a quantifiable dollar figure, the damage here is best measured as **total loss of token value / market capitalization** for BEC — a full collapse rather than a partial theft, since the exploit itself did not "drain" a pool of funds but instead destroyed the token's scarcity and thus its worth entirely.

## Description of the Contract and the Vulnerable Function

**Contract:** `BecToken` (inherits `PausableToken` → `StandardToken` → `ERC20`)
**Function:** `batchTransfer(address[] _receivers, uint256 _value)`

```solidity
function batchTransfer(address[] _receivers, uint256 _value) public whenNotPaused returns (bool) {
    uint cnt = _receivers.length;
    uint256 amount = uint256(cnt) * _value;                 // <-- VULNERABLE LINE
    require(cnt > 0 && cnt <= 20);
    require(_value > 0 && balances[msg.sender] >= amount);

    balances[msg.sender] = balances[msg.sender].sub(amount);
    for (uint i = 0; i < cnt; i++) {
        balances[_receivers[i]] = balances[_receivers[i]].add(_value);
        Transfer(msg.sender, _receivers[i], _value);
    }
    return true;
}
```

**Purpose:** Allow a token holder to send an identical `_value` amount to up to 20 recipients in one call, debiting the sender's balance once for the combined total instead of issuing 20 separate `transfer()` calls.

**Root cause:** The line `uint256 amount = uint256(cnt) * _value;` uses plain Solidity multiplication rather than `SafeMath.mul()`. Solidity ^0.4.x (the compiler version used) performs **no automatic overflow checks**, so `cnt * _value` can wrap silently around the 256-bit boundary. Since both `cnt` and `_value` are fully attacker-controlled, an attacker can choose values whose product overflows to exactly `0`, defeating the balance check that immediately follows and enabling the loop to credit large token amounts to arbitrary addresses with no real debit ever occurring. Notably, the same contract *does* use `SafeMath` correctly for `.sub()` and `.add()` a few lines later — the overflow-checked library simply was not applied consistently to every arithmetic operation in the function.

## Reference Section

### Contract & Transaction (Etherscan)
- **BecToken contract address:** `0xC5d105E63711398aF9bbff092d4B6769C82F793D`
- **Verified source code (canonical):** https://etherscan.io/address/0xc5d105e63711398af9bbff092d4b6769c82f793d#code
- **Exploit transaction:** https://etherscan.io/tx/0xad89ff16fd1ebe3a0a7cf4ed282302c06626c1af33221ebe0d3a470aba4a660

### Repository / Reference Mirrors
- https://github.com/uni-due-syssec/evmpatch-eval-data/tree/master/CVE-comparison/batchOverflow_BecToken — academic dataset benchmarking bytecode-level vs. source-level patches for this exact CVE
- https://github.com/ylevalle/SolidityOverflow/blob/main/BECtoken.sol — reproduction of the vulnerable contract in an overflow/underflow teaching repo
- https://github.com/solidity-korea/solidity-A-to-Z/blob/master/contracts/BEC-overflow.sol — teaching mirror of the same CVE

### Original Disclosure & Analysis
- PeckShield — "New batchOverflow Bug in Multiple ERC20 Smart Contracts (CVE-2018-10299)": https://blog.peckshield.com/2018/04/22/batchOverflow/
- SECBIT Media (Medium) — "A disastrous vulnerability found in smart contracts of BeautyChain (BEC)": https://medium.com/secbit-media/a-disastrous-vulnerability-found-in-smart-contracts-of-beautychain-bec-dbf24ddbc30e

## Lessons Learned

1. **Apply overflow-safe arithmetic consistently, not selectively.** The contract already imported and used `SafeMath` for `sub()` and `add()`, but the critical `cnt * _value` multiplication was left as raw arithmetic. A single unchecked operation was enough to undermine the entire access-control logic. Every arithmetic operation that feeds into a security-relevant check must be protected — partial coverage offers no real protection.

2. **Never trust a computed value used in a `require()` guard if its inputs are fully attacker-controlled.** The check `balances[msg.sender] >= amount` was only as trustworthy as the correctness of `amount`'s calculation. When both operands of an arithmetic expression can be freely chosen by the caller, that expression is a prime target for boundary manipulation (overflow/underflow, division tricks, rounding).

3. **Audit "convenience" functions as rigorously as core transfer logic.** `batchTransfer` was a non-standard, contract-specific addition layered on top of a fairly standard ERC-20 base. Custom extensions to well-audited standards often receive less scrutiny than the base implementation, even though they introduce new attack surface.

4. **Use compiler/language-level protections where available.** This class of bug is structurally eliminated in Solidity ≥0.8.0, which reverts on overflow/underflow by default. Contracts on older compiler versions should either upgrade or enforce `SafeMath` (or equivalent) on every single arithmetic operation without exception, ideally enforced via linters/static analysis in CI.

5. **Static analysis tools should specifically flag multiplications feeding into balance/authorization checks.** Contemporary tools (Oyente, at the time) initially missed this exact vulnerable line, showing that generic "integer overflow" detectors need to also reason about *where* the overflowed value is subsequently used (e.g., as an implicit access-control gate), not just flag raw arithmetic.

6. **Immutable deployed contracts leave no room for a "patch."** Once identified, the only real-world mitigations were reactive: exchanges halting trading and withdrawals. This underscores the necessity of pre-deployment audits, testnet fuzzing, and formal verification (as later demonstrated by firms like CertiK) — post-deployment response can only limit damage, not prevent it.

7. **Bug patterns propagate through code reuse.** Because BEC's `batchTransfer` code was copied into numerous other ERC-20 tokens, the same flaw affected many separate projects simultaneously. Copy-pasted contract code should be treated as carrying the same risk profile as the original — including any latent vulnerabilities — and re-audited rather than assumed safe by association.
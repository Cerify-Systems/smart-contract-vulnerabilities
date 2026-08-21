# Fix 

## What SmartMesh / the ecosystem did

- SmartMesh worked with exchanges to identify and blacklist/void the counterfeit balances
  created by the attack, and coordinated with Huobi and others, who had already flagged the
  transactions as "abnormal" and declined to credit user deposits/withdrawals of the
  fabricated tokens.
- Exchanges broadly suspended ERC-20 deposits and withdrawals across many tokens (not just
  SMT/BEC) while they audited which other listed tokens shared the same vulnerable pattern.
- Longer term, SmartMesh and other affected projects migrated to fixed contract logic (or
  new token contracts entirely) using overflow-safe arithmetic.

## The actual code fix

Use checked/safe arithmetic everywhere token balances are computed. The canonical
contemporary fix was OpenZeppelin's `SafeMath`:

```solidity
using SafeMath for uint256;

function transferProxy(address _from, address _to, uint256 _value, uint256 _feeSmt,
    uint8 _v, bytes32 _r, bytes32 _s)
    public transferAllowed(_from) returns (bool)
{
    uint256 total = _value.add(_feeSmt); // reverts on overflow instead of wrapping
    require(balances[_from] >= total, "insufficient balance");

    uint256 nonce = nonces[_from];
    bytes32 h = keccak256(abi.encodePacked(_from, _to, _value, _feeSmt, nonce));
    require(_from == ecrecover(h, _v, _r, _s), "invalid signature");

    balances[_to] = balances[_to].add(_value);
    balances[msg.sender] = balances[msg.sender].add(_feeSmt);
    balances[_from] = balances[_from].sub(total);
    nonces[_from] = nonce + 1;

    emit Transfer(_from, _to, _value);
    emit Transfer(_from, msg.sender, _feeSmt);
    return true;
}
```

Since Solidity 0.8.0 (2020), arithmetic overflow/underflow reverts by default, which closes
this entire bug class at the language level for newly-compiled contracts but any contract
still compiled with an older `pragma solidity` version, or that wraps arithmetic in an
`unchecked { ... }` block, remains exposed.

## Recommended structural fixes

1. **Use checked arithmetic everywhere.** Either target Solidity ≥0.8.0 without `unchecked`
   blocks around balance math, or use `SafeMath`/equivalent on older compilers. There is
   essentially never a good reason for raw arithmetic on user-supplied values that affect
   token balances.

2. **Validate assumptions, don't just check derived values.** The original guard checked
   `balances[_to] + _value < balances[_to]` (an overflow check on the *wrong* addition) —
   auditors should trace every arithmetic expression back to its actual overflow risk rather
   than trusting that "a check exists nearby."

3. **Minimize custom "gasless transfer" / meta-transaction logic.** These patterns
   (`transferProxy`, `batchTransfer`, `permit`-style delegated calls) are not part of the
   ERC-20 standard and were, at the time, frequently rolled by hand with subtle bugs. Prefer
   audited, standardized implementations (e.g. EIP-2612 `permit`, OpenZeppelin's
   `ERC20Permit`) over bespoke fee/signature/nonce logic.

4. **Fuzz/property-test arithmetic boundaries.** A property test asserting
   `balanceOf(from) after == balanceOf(from) before - value - fee` for randomized large
   `uint256` inputs (including values chosen to overflow) would have caught this
   immediately.

5. **Exchange-side sanity limits.** Independent of the contract fix, exchanges adopted
   circuit breakers to reject/flag deposits of implausibly large token amounts relative to a
   token's known total supply a useful defense-in-depth layer against this entire bug
   class, including future undiscovered variants.

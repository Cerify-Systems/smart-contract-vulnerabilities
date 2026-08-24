# Fix

## Root Cause to Fix

The vulnerability came from inconsistent accounting between:

- stored pool reserves (`baseAmount` / `tokenAmount`), and
- live ERC-20 balances (`balanceOf(pool)`).

The redemption path priced LP units from the live balance while reserve accounting continued to use the stored values. An attacker could donate tokens directly to the pool, inflate the live balance, and redeem against that inflated number.

## 1. Use Synchronized Reserves for LP Shares

`calcLiquidityShare()` should not use an attacker-controlled raw `balanceOf(pool)` as the economic reserve.

LP redemption should instead be based on the same synchronized reserve values used by the protocol's liquidity accounting.

Conceptually:

```text
share = units / totalSupply

outputBase  = storedBaseReserve  × share
outputToken = storedTokenReserve × share
```

## 2. Reconcile Unsolicited Transfers

If the protocol chooses to use live token balances, it must reconcile them before performing any reserve-dependent calculation.

A safe design must explicitly decide what happens to unsolicited tokens:

- distribute them proportionally to all LP holders,
- skim them to a protocol-controlled destination,
- or incorporate them into reserves before calculating shares.

The important requirement is that the next LP redeemer must not receive the entire economic benefit of an arbitrary donation.

## 3. Keep Mint and Burn Accounting Symmetric

The same valuation basis must be used when issuing and redeeming LP units.

Avoid:

```text
mint -> stored reserves
burn -> spot balance
```

Prefer:

```text
mint -> synchronized reserves
burn -> synchronized reserves
```

## 4. Add Invariant Tests

The protocol should test properties such as:

```text
A user cannot redeem more than their proportional share
of the synchronized reserves.
```

A useful fuzz/property test should:

1. create a pool;
2. add liquidity;
3. transfer arbitrary tokens directly to the pool;
4. attempt to redeem LP units;
5. verify that the unsolicited donation cannot be captured unfairly by one LP.

## 5. Test Donation/Sync Edge Cases

The following cases should be explicitly covered:

- direct token transfer to the pool;
- donation followed immediately by `removeLiquidity`;
- donation followed by `addLiquidity`;
- donation followed by `sync`;
- repeated add/remove cycles;
- flash-loan-funded balance manipulation;
- zero-liquidity and very small-liquidity pools.

## 6. Protect Upgradeable Math

Spartan's architecture separated core arithmetic into the `UTILS` contract. The project documentation itself notes that `UTILS` contains core pool arithmetic and can be upgraded by governance.

Any future Utils upgrade should therefore receive:

- independent review;
- regression testing against the previous version;
- invariant/property-based testing;
- mainnet-fork testing;
- explicit review of liquidity mint/burn calculations.

## Remediation After the Incident

Spartan Protocol's May 2021 development report states that, after the attack and analysis with PeckShield, an update to the Utils contract was deployed to prevent repeated use of the identified `calcLiquidityShare` attack vector.

A later independent reproduction found additional risk while the remediation was being deployed and documented the final patch timeline, highlighting why the fix needed to preserve legitimate liquidity removal while closing the accounting flaw.

## Lessons Learned

The most important lesson is that a pool must never implicitly treat its raw ERC-20 balance as trusted accounting state.

An attacker can always send tokens to a contract address.

Security-critical calculations should therefore rely on explicit, synchronized state and enforce the same accounting model across:

- liquidity deposits;
- liquidity withdrawals;
- swaps;
- reserve updates;
- donations;
- and synchronization operations.

# Source Code Analysis — Alpha Homora V2 / Iron Bank

## Incident

Date:

13 February 2021

Protocol:

Alpha Homora V2

External lending protocol:

C.R.E.A.M. V2 Iron Bank

Loss:

Approximately $37.5–38 million

## Primary Vulnerability

The exploit was a combination of multiple accounting and access-control
weaknesses.

The important conditions were:

1. An sUSD lending pool existed at the contract level.
2. The sUSD pool had no liquidity.
3. The attacker could become the sole borrower.
4. Borrow calculations contained a rounding error.
5. `resolveReserve()` could be called by anyone.
6. `resolveReserve()` could increase `totalDebt` without increasing
   `totalDebtShare`.
7. HomoraBank accepted arbitrary custom spells.

## 1. Empty sUSD Pool

The vulnerable HomoraBank deployment contained an sUSD lending pool that
was not yet exposed through the user interface.

The pool had no meaningful lending liquidity.

This was important because the attacker could control the pool's debt
state without competing borrowers.

## 2. Borrow Rounding

The borrowing calculation used debt shares.

Conceptually:

    debtShare =
        amount * totalDebtShare / totalDebt

The division truncates the result.

When the attacker was the sole borrower, this rounding behavior became
significant.

## 3. Creating a Residual Debt Share

The attacker initially borrowed approximately:

    1,000 sUSD

The attacker then repaid slightly less than the exact amount required.

Because of the rounding behavior, the repayment did not completely remove
the borrower's debt share.

The attacker could therefore remain the sole borrower with a very small
borrow share.

## 4. resolveReserve()

The attacker then called:

    resolveReserve()

The function was intended to account for accumulated revenue and move it
into the reserve.

In the vulnerable deployment, the function could be called by anyone.

More importantly, it could increase:

    totalDebt

without increasing:

    totalDebtShare

This created a highly distorted debt state.

Example:

    totalDebt      = very large
    totalDebtShare = 1

## 5. Borrowing Against the Distorted State

With a single debt share, the attacker could repeatedly call the borrowing
logic.

The debt-share calculation rounded the attacker's new share down.

As a result, the protocol could treat additional borrowing as having little
or no additional debt share.

The attacker could therefore increase the amount of assets borrowed while
keeping the recorded debt-share impact extremely small.

## 6. Exponential Debt Growth

The attack repeated this process.

Each cycle increased the effective debt amount.

The attacker exploited the relationship between:

    totalDebt

and:

    totalDebtShare

to create increasingly large borrowing capacity.

## 7. Custom Spell

HomoraBankV2 allowed users to provide custom spells.

A spell is a strategy contract used by Alpha Homora to execute operations
such as:

- borrowing
- repaying
- adding collateral
- interacting with external protocols

The vulnerable system did not require the spell to be on a strict
whitelist.

The attacker therefore deployed a malicious spell:

    0x560a8e3b79d23b0a525e15c6f3486c6a293ddad2

## 8. Iron Bank Integration

Alpha Homora V2 used C.R.E.A.M. V2 Iron Bank for protocol-to-protocol
lending.

The attacker used the inflated borrowing capability to obtain assets
through Alpha's Iron Bank relationship.

The extracted assets included:

    ETH
    DAI
    USDC
    USDT

## 9. Final Extraction

The attacker moved the borrowed assets out of the affected system.

The attack involved more than nine transactions and used flash loans and
multiple DeFi protocols.

The additional debt was ultimately owed by:

    Alpha Homora V2

to:

    C.R.E.A.M. V2 Iron Bank

## Root Cause

There was no single isolated bug.

The exploit required the combination of:

    rounding error
          +
    permissionless resolveReserve()
          +
    zero-liquidity lending pool
          +
    unrestricted custom spells
          +
    protocol-to-protocol credit

## Vulnerability Classification

Primary:

- Accounting manipulation
- Rounding error
- Improper access control
- Unrestricted custom strategy execution

Secondary:

- Flash-loan-assisted attack
- Cross-protocol lending abuse
- Protocol-to-protocol credit exploitation

## Remediation

Alpha subsequently:

- restricted `execute()` access,
- allowed only whitelisted spells,
- restricted `resolveReserve()` to governance,
- removed borrowing/repaying functionality for unreleased assets,
- paused borrowing while the issue was investigated.

These changes are documented in Alpha's subsequent incident updates.

## Security Lesson

Financial protocols must not assume that individually small accounting
errors are harmless.

Rounding behavior can become catastrophic when:

- one borrower controls the entire pool,
- debt shares are used for accounting,
- total debt can change independently,
- and repeated borrowing is possible.

Access-control checks are equally important for accounting functions such as
`resolveReserve()`.

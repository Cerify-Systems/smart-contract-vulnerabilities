
The attack sequence and asset amounts are documented by CertiK and other incident analyses. :contentReference[oaicite:8]{index=8}

---

# `sources/source-code-analysis.md`

```md
# Source Code Analysis — Moola Market

## 1. LendingPool

The Moola V2 LendingPool is responsible for:

- deposits
- withdrawals
- borrowing
- repayment
- liquidation
- collateral management

The important security property for this incident is that borrowing
capacity depends on the value of the user's collateral.

Therefore, the price returned by the configured oracle directly affects
the amount an attacker can borrow.

## 2. MoolaOracle

MoolaOracle acts as the protocol-level price oracle.

For an asset, the oracle:

1. Finds the configured price source.
2. Calls the source's `getAssetPrice()`.
3. Uses the returned value if it is greater than zero.
4. Otherwise uses the fallback oracle.

The relevant architecture is:

    LendingPool
        |
        v
    MoolaOracle
        |
        v
    UbeswapPriceProvider
        |
        v
    Ubeswap price feed

## 3. UbeswapPriceProvider

UbeswapPriceProvider maintains a mapping:

    asset -> priceFeed

The price provider obtains the asset price by calling:

    priceFeed.consult()

Therefore, the MOO valuation ultimately depended on the configured
Ubeswap price-feed mechanism.

## 4. Economic Weakness

The vulnerability was not a simple Solidity memory/storage bug.

The weakness was economic.

MOO had relatively low liquidity on Ubeswap.

The attacker could therefore buy MOO and significantly increase its
market price.

If the manipulated price was used for collateral valuation, the
attacker's MOO holdings appeared to be worth substantially more than
their realistic market value.

## 5. Manipulation

The attacker repeatedly traded MOO against CELO.

This increased the observed MOO price.

The reported price moved from approximately:

    $0.018

to:

    $0.65

This was a large artificial increase.

## 6. Collateral Valuation

After manipulating the MOO market, the attacker used MOO as collateral.

The lending protocol queried its oracle.

The oracle returned the manipulated market price.

Therefore:

    MOO quantity × manipulated price
        =
    inflated collateral value

The attacker consequently received a much larger borrowing capacity.

## 7. Borrowing

The attacker borrowed several assets using the inflated MOO collateral.

Reported assets included:

- CELO
- cUSD
- cEUR
- MOO

The resulting debt was not backed by economically sufficient collateral
once the MOO market returned toward its real value.

## 8. Root Cause

The root cause can be summarized as:

    manipulable market
          +
    oracle dependence
          +
    MOO accepted as collateral
          +
    insufficient risk parameters

## 9. Classification

Primary:

- Oracle manipulation
- Market-price manipulation
- Economic attack
- Collateral valuation failure

Secondary:

- Low-liquidity collateral
- Flash-loan-assisted capital amplification
- Cross-protocol dependency

## 10. Mitigation

A more robust design would include one or more of:

- Chainlink or another independent oracle
- Multiple independent price sources
- Long-window TWAP
- Liquidity-aware pricing
- Maximum price-deviation checks
- Conservative LTV for low-liquidity assets
- Removing MOO from collateral eligibility

## 11. Post-Incident Changes

Moola subsequently removed MOO as a collateral asset.

Governance communications also described fixing asset oracle prices at
pre-attack values and adjusting risk parameters before restoring the
protocol.

## 12. Security Lesson

Oracle security is not only about whether a price feed returns a valid
number.

The protocol must evaluate whether an economically rational attacker can
move the underlying market enough to make the returned number unsafe for
lending decisions.
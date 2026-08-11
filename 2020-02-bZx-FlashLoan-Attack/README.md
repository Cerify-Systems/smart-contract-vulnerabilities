# bZx Flash Loan Attack — February 2020

## Incident

- Date: 15 February 2020
- Protocol: bZx / Fulcrum
- Chain: Ethereum
- Loss: Approximately $355,000
- Attack Profit: Approximately 1,271 ETH
- Vulnerability: Position-health / slippage validation bypass
- Attack Technique: Flash Loan + Leveraged Trade + DEX Price Impact
- Main Protocols: dYdX, Compound, bZx, Kyber and Uniswap

## Summary

On 15 February 2020, an attacker exploited bZx/Fulcrum through a single atomic transaction involving several DeFi protocols.

The attacker borrowed 10,000 ETH from dYdX using a flash loan.

The borrowed ETH was divided between Compound and bZx.

5,500 ETH was deposited into Compound and used to borrow approximately 112 WBTC.

The attacker then deposited 1,300 ETH into bZx and opened a 5x leveraged short position.

The bZx trade interacted with Kyber, which routed liquidity through Uniswap.

The large trade caused extreme WBTC/ETH price slippage.

The resulting bZx position became severely under-collateralized.

Normally, bZx's position-health check should have rejected the trade.

However, a flaw in the conditional logic caused the `shouldLiquidate()` validation to be skipped for the attacker's execution path.

The trade therefore completed despite the position being under-collateralized.

The attacker subsequently sold the WBTC borrowed from Compound at the favorable price and used the resulting ETH to repay the dYdX flash loan.

## Attack Flow

```text
dYdX
  │
  │ 10,000 ETH flash loan
  ▼
Attacker
  │
  ├─────────────── 5,500 ETH ──────► Compound
  │                                    │
  │                                    └──► 112 WBTC
  │
  └─────────────── 1,300 ETH ──────► bZx
                                       │
                                       ▼
                              marginTradeFromDeposit()
                                       │
                                       ▼
                                  Kyber / Uniswap
                                       │
                                       ▼
                              Extreme price slippage
                                       │
                                       ▼
                              Under-collateralized
                                  bZx position
                                       │
                                       ▼
                              Health check bypassed
                                       │
                                       ▼
Attacker sells 112 WBTC ───────────► Uniswap
                                       │
                                       ▼
                                  ~6,871 ETH
                                       │
                                       ▼
                               dYdX flash loan
                                  repayment
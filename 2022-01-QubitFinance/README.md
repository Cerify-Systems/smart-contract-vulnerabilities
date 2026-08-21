# 2022-01 — Qubit Finance (QBridge) Exploit

| **Protocol** | Qubit Finance (BSC lending market + QBridge cross-chain bridge) |
| **Date** | January 27–28, 2022 (~21:34 UTC start) |
| **Chains** | Ethereum ↔ Binance Smart Chain |
| **Loss** | ~$80 million (206,809 BNB drained; 77,162 qXETH minted illegitimately) |
| **Root cause** | Improper validation of `tokenAddress == address(0)` in `QBridgeHandler.deposit()`, combined with a non-standard `safeTransferFrom` that silently succeeds when called on the zero address |
| **Category** | Access control / input validation — cross-chain bridge deposit spoofing |
| **Attacker address (ETH)** | `0xdb3E6CC3ffe9d5EF0AF1D3D68F49Eb6d7f0Cfc3f`-style funded via Tornado Cash (see writeups) |

## Folder layout

```
2022-01-QubitFinance/
├── README.md          (this file)
├── exploit.md          Step-by-step breakdown of the attack
├── fix.md               How Qubit Finance / the ecosystem should have prevented it
├── summary.md          One-page executive summary
├── contracts/
│   ├── QBridge.sol                 Entry point contract, forwards deposit() to handler
│   ├── QBridgeHandler.sol          Vulnerable resource/token-mapping + deposit logic
│   ├── IQBridgeHandler.sol         Interface
│   ├── SafeToken.sol                      
└── writeups/
    └── sources.md       Links to primary post-mortems used to build this folder
```

## One-line summary

An attacker called `deposit()` on the Ethereum-side `QBridgeHandler` with the token address set to `address(0)` (which was mistakenly left whitelisted after ETH-native deposits were added) and no attached ETH. Because the handler's custom transfer helper doesn't revert when the target has no contract code, the "deposit" appeared to succeed with zero real value moved, while the BSC side dutifully minted 77,162 qXETH against it. The attacker then borrowed/converted that fake collateral into BNB, ETH, BTC-B, stablecoins and other assets — draining roughly $80M from the protocol.

See `exploit.md`, `fix.md`, and `summary.md` for details.

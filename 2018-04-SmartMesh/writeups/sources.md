# Primary Sources

- PeckShield — "Integer Overflow (i.e., proxyOverflow Bug) Found in Multiple ERC20 Smart
  Contracts (CVE-2018-10376)"
  https://peckshield.medium.com/integer-overflow-i-e-proxyoverflow-bug-found-in-multiple-erc20-smart-contracts-14fecfba2759
  (mirror: https://blog.peckshield.com/2018/04/25/proxyOverflow/)
- Verichains Lab — "Integer overflow, simple but not easy" (joint batchOverflow /
  proxyOverflow analysis)
  https://blog.verichains.io/p/integer-overflow-simple-but-not-easy-9ebbc58bbaa5
- Wolf Crypto — "Wolf Crypto's assessment of the recent ERC20 batchOverflow and
  proxyOverflow vulnerabilities"
  https://medium.com/wolf-crypto/batchoverflow-erc20-vulnerability-5691e42940de
- CryptoJobsList — "Why you should verify the tokens you own: A deep dive into two
  vulnerable ERC20 contracts" (BEC + SMT walkthrough with real transaction data)
  https://cryptojobslist.com/blog/two-vulnerable-erc20-contracts-deep-dive-beautychain-smartmesh
- Cypher Core — "Replay Attack Vulnerability in Ethereum Smart Contracts Introduced by
  transferProxy()"
  https://medium.com/cypher-core/replay-attack-vulnerability-in-ethereum-smart-contracts-introduced-by-transferproxy-124bf3694e25
- CoinDesk — "Crypto Exchanges Pause Services Over Contract Bugs"
  https://www.coindesk.com/markets/2018/04/25/crypto-exchanges-pause-services-over-contract-bugs
- Etherscan — SmartMesh (SMT) token contract, verified source
  https://etherscan.io/token/0x55f93985431fc9304077687a35a1ba103dc1e081
- CVE-2018-10376 (proxyOverflow) / CVE-2018-10299 (batchOverflow, the BeautyChain/BEC
  sibling bug found two days earlier)

## Note on the `contracts/` folder

`SMT.sol` reproduces the verified `transferProxy()` function body from Etherscan verbatim
(it is short, public, on-chain, and central to understanding the bug); the surrounding
ERC-20 boilerplate (name/symbol/balances/constructor) is reconstructed for context and
compilability rather than a full copy of the deployed contract. `SMT_fixed.sol` shows the
same function patched with checked arithmetic, for comparison.

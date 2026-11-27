# UniCats (MEOW) Exploit — Unlimited Token Approval + Backdoor Governance Function

**Date:** September 2020  
**Chain:** Ethereum Mainnet  
**Category:** Malicious/backdoored smart contract + unlimited ERC-20 approval abuse  
**Estimated Loss:** ~$140,000 worth of UNI tokens

---

## 1. Overview

UniCats (`unicat.farm`) launched during the "DeFi Summer" of 2020 as a yield-farming platform, cloned from Sushiswap's frontend, that let users stake **UNI** (and various UNI liquidity pool tokens) to earn a native reward token called **MEOW**. To participate, users had to approve the UniCats staking contract to spend their UNI — and, like most farms of that era, the default flow requested an **unlimited (`type(uint256).max`) ERC-20 allowance** rather than an amount scoped to the actual deposit.

The contract owner had embedded a disguised backdoor function (`setGovernance`) inside the staking contract. This function was used to make the UniCats contract issue arbitrary calls — including `transferFrom` calls against the UNI token contract — silently draining tokens from any wallet that had granted it approval, whether or not that wallet had ever deposited funds.

---

## 2. Why This Vulnerability Happened

Two independent weaknesses combined to make this exploit possible:

1. **Malicious/backdoored contract logic.** The staking contract shipped with an admin-only function, `setGovernance(address _governance, bytes memory _setupData)`, that on the surface looked like ordinary governance-configuration logic (many legitimate DeFi protocols have a similarly named function for pointing at a governance module). In UniCats, this function instead let the owner target **any address** with **arbitrary calldata**, executed as a call originating from the UniCats contract itself. There was no restriction on which contracts it could call or what functions it could invoke.

2. **Unlimited token approvals from users.** Because users approved UniCats for the maximum possible UNI allowance instead of the exact amount they intended to stake, the contract had standing permission to move a user's **entire UNI balance** at any time — not just the deposited portion. This turned a hidden bug/backdoor in one function into a total-wallet-drain vector instead of a bounded, worst-case loss.

Neither weakness alone would have caused this scale of loss: a backdoor without approvals could only move funds already inside the contract, and unlimited approvals without a backdoor would just be latent risk. Together, they gave the attacker a direct pipeline from "arbitrary call" to "arbitrary transfer out of victims' wallets."

---

## 3. Attack Flow

```
1. UniCats is deployed and marketed as a UNI/LP-token yield farm (MEOW rewards).
   - Frontend cloned from Sushiswap to appear legitimate.

2. Users are enticed to stake UNI and various UNI LP tokens to earn MEOW.
   - To deposit, users must first call approve() on the UNI token contract,
     granting UniCats an UNLIMITED allowance (uint256 max).

3. Many users approve and/or deposit UNI into the UniCats contract.

4. Attacker ("Whiskers") calls the backdoor function on the UniCats contract:

       setGovernance(
           _governance = <UNI token contract address>,
           _setupData  = abi.encodeCall(
               IERC20.transferFrom,
               (victimWallet, uniCatsContract, amount)
           )
       )

5. Internally, setGovernance forwards _setupData as a low-level call to
   _governance (the UNI contract), with UniCats as msg.sender:

       (bool success, ) = _governance.call(_setupData);

6. Because msg.sender in that call is the UniCats contract — which holds
   unlimited allowance from the victim — the UNI contract executes the
   transferFrom successfully, moving tokens straight out of the victim's
   wallet into UniCats' control.

7. This is repeated across many approved wallets, including wallets that
   never deposited, or had already withdrawn, since the approval itself
   (not the deposit) was the exploitable asset.

8. Funds are funneled out, in part laundered through Tornado Cash,
   and converted to ETH.
```

**Key insight:** The victim never signs a second malicious transaction. The only transaction the victim ever authorized was the original `approve()` call. Everything after that is executed unilaterally by the attacker using the standing allowance — which is why these drains show no suspicious outgoing activity initiated by the victim.

---

## 4. Vulnerable Contract & Function

- **Contract:** UniCatFarm (staking/farming contract)
- **Address (Ethereum Mainnet):** [`0xB246bcD5bAac8E342941d0f803d528b6668E42Cd`](https://etherscan.io/address/0xB246bcD5bAac8E342941d0f803d528b6668E42Cd#code)
- **Related token contract:** UniCat.farm (MEOW) — [`0xEc13f3c54Feebfb0601934c9Ff70A61Ba8a8Ed8f`](https://etherscan.io/address/0xEc13f3c54Feebfb0601934c9Ff70A61Ba8a8Ed8f#code)
- **Faulty function:** `setGovernance(address _governance, bytes memory _setupData)`
  - Access control: restricted to `onlyOwnerOrGovernance`
  - Behavior: forwards `_setupData` as an arbitrary low-level call to `_governance`, with the UniCats contract as the caller — no restriction on target contract or function selector.


---

## 5. Impact / Loss Incurred

- **~$140,000** worth of UNI tokens stolen from users who had granted unlimited approvals to the UniCats contract.
- Victims included users who had **never deposited** into the farm, or who had already **withdrawn** — the unlimited approval alone was sufficient exposure.
- The incident became a widely cited case study for the dangers of unlimited ERC-20 allowances in DeFi, referenced in later academic research on approval-based attack vectors (e.g., quantifying unlimited-approval risk on Ethereum).
- Reputational damage to the broader "food-themed DeFi fork" trend of 2020, many of which were later identified as low-effort scams or unaudited clones.

---

## 6. Fix / Mitigation

There was no patch to the UniCats contract itself — it was a deliberately malicious/backdoored deployment, not a bug in an otherwise honest protocol, so "fixing" it meant remediation at the ecosystem and user level rather than a code fix by the project:

- **User-side revocation:** Affected users were advised to immediately revoke the UniCats contract's UNI allowance (e.g., via Etherscan's "Token Approvals" page or tools like Revoke.cash) to cut off further exposure.
- **Ecosystem-level mitigations that emerged from this class of incident:**
  - Wallets and dapp frontends increasingly defaulting to **exact-amount approvals** instead of unlimited allowances.
  - Wider adoption of **approval-monitoring/revocation tools** (Revoke.cash, Etherscan Token Approval Checker) as standard wallet hygiene.
  - Security guidance from wallet providers (e.g., MetaMask) explicitly warning users about the risk of unlimited/blanket token approvals.
  - Increased emphasis on **auditing before granting approvals**, since an allowance persists independently of whether a user continues to trust or use the dapp.
  - Adoption of **ERC-2612 (permit)**-style signature-based approvals and time/amount-bounded allowances in newer protocol designs to reduce standing-allowance risk.

**General best practice reinforced by this incident:** Never grant unlimited token approvals to a contract unless it is well-audited and trusted long-term; approve only the amount required for the immediate transaction, and periodically review/revoke stale approvals.

---

## 7. References

- ZenGo — ["UniCats Go Phishing"](https://zengo.com/unicats-go-phishing/) (full technical breakdown of the `setGovernance` exploit)
- Kalis.me — ["Unlimited ERC20 allowances considered harmful"](https://kalis.me/unlimited-erc20-allowances/)
- ACM — ["Penny Wise and Pound Foolish: Quantifying the Risk of Unlimited Approval of ERC20 Tokens on Ethereum"](https://dl.acm.org/doi/fullHtml/10.1145/3545948.3545963)
- Smart Contract Security Field Guide — [Approval Vulnerabilities](https://scsfg.io/hackers/approvals/)
- MetaMask Help Center — [What is a malicious token approval?](https://support.metamask.io/stay-safe/safety-in-web3/what-is-a-malicious-token-approval/)
- Etherscan — [UniCatFarm contract source](https://etherscan.io/address/0xB246bcD5bAac8E342941d0f803d528b6668E42Cd#code)
- Etherscan — [UniCat.farm (MEOW) token contract source](https://etherscan.io/address/0xEc13f3c54Feebfb0601934c9Ff70A61Ba8a8Ed8f#code)
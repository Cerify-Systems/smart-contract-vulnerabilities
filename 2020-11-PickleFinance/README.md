# Pickle Finance Exploit (November 2020)

## Overview

**Pickle Finance** is a DeFi yield-aggregation protocol on Ethereum. It allows users to deposit assets into "Jars" (analogous to Yearn Vaults) which route funds into yield-generating strategies across protocols like Compound and Curve. The protocol also issues the PICKLE governance token to liquidity providers.

On **November 21, 2020**, Pickle Finance was exploited for approximately **19.76 million DAI (~$19.7M)**, drained from its `pDAI` Jar. The attack is widely regarded as one of the more sophisticated DeFi exploits of that era, involving multiple custom-deployed malicious contracts and a multi-step transaction sequence rather than a single flash-loan price manipulation.

## The Exploit

The attacker:
1. Deployed fake "Jar" contracts that mimicked the interface of legitimate Pickle Jars.
2. Used these fake Jars, via the `ControllerV4.swapExactJarForJar()` function, to trick the Controller into withdrawing real DAI from the legitimate `StrategyCmpdDaiV2` strategy.
3. Repeated the process with additional fake contracts to redirect the withdrawn funds (first as DAI, later as cDAI after triggering `earn()`) into a Jar entirely under the attacker's control.
4. Redeemed the stolen cDAI for DAI on Compound and withdrew ~19.76M DAI to an externally owned account.

## Root Cause

The root cause was a **missing access-control / whitelist check** in `ControllerV4.swapExactJarForJar()`. The function accepted `_fromJar` and `_toJar` addresses supplied directly by the caller and never validated that these addresses corresponded to real, registered Pickle Jars (i.e., it never checked them against the Controller's own `jars` mapping, unlike other functions in the same contract such as `withdraw()`).

Because the addresses were trusted without verification, the attacker could deploy a contract that satisfied the `IJar` interface but returned attacker-chosen values (token address, conversion ratio, decimals). This let the attacker's fake Jar impersonate the real DAI Jar and cause the Controller to release genuine funds from the real strategy.

A secondary contributing factor was the use of `delegatecall` inside `_execute()`, which runs attacker-supplied calldata in the Controller's own storage context — turning the "converter" execution step from a contained utility call into a vector for broader unauthorized state manipulation once the initial trust boundary was breached.

## Vulnerable Contract: `ControllerV4.sol`

- **Contract address:** `0x6847259b2B3A4c17e7c43C54409810aF48bA5210`
- **Compiler:** Solidity `^0.6.7`, `ABIEncoderV2`

### Functions Involved

**`swapExactJarForJar()`** — the primary vulnerable function.
```solidity
function swapExactJarForJar(
    address _fromJar,
    address _toJar,
    uint256 _fromJarAmount,
    uint256 _toJarMinAmount,
    address payable[] calldata _targets,
    bytes[] calldata _data
) external returns (uint256) {
    ...
    address _fromJarToken = IJar(_fromJar).token();
    address _toJarToken = IJar(_toJar).token();
    ...
}
```
While `_targets` (converter addresses) were checked against `approvedJarConverters`, `_fromJar` and `_toJar` were never checked against the Controller's `jars` registry. This is the core omission that made the attack possible.

**`_execute()`** — the internal helper that amplified the impact.
```solidity
function _execute(address _target, bytes memory _data)
    internal
    returns (bytes memory response)
{
    require(_target != address(0), "!target");
    assembly {
        let succeeded := delegatecall(
            sub(gas(), 5000),
            _target,
            add(_data, 0x20),
            mload(_data),
            0,
            0
        )
        ...
    }
}
```
Called in a loop from `swapExactJarForJar()`, this function executes caller-supplied calldata via `delegatecall` against an approved converter address — running with the Controller's own storage and authority. Combined with the missing Jar validation, this allowed the attacker's crafted calldata to manipulate Controller state well beyond a simple token conversion.

**`withdraw()`** — shown for contrast; this function *does* correctly validate the caller against the `jars` mapping (`require(msg.sender == jars[_token], "!jar")`), illustrating that the validation pattern existed elsewhere in the contract but was omitted in `swapExactJarForJar()`.

## References

- Contract (Etherscan, verified source): https://etherscan.io/address/0x6847259b2B3A4c17e7c43C54409810aF48bA5210#code
- Post-mortem write-up: https://github.com/banteg/evil-jar/blob/master/readme.md
- Deployed contracts registry (community-maintained): https://github.com/developerfred/-pickle-finance-contracts
- Base architecture Pickle's Jars/Controller were forked from: https://github.com/iearn-finance/jars
- Attack transaction: https://etherscan.io/tx/0xe72d4e7ba9b5af0cf2a8cfb1e30fd9f388df0ab3da79790be842bfbed11087b0
- Attacker addresses:
  - https://etherscan.io/address/0x75aa95508f019997aeee7b721180c80085abe0f9
  - https://etherscan.io/address/0x02c8364546ec849e1726fb6cae5228702b111ee6
- Pickle Finance official incident disclosure: https://picklefinance.medium.com/pickle-was-hacked-and-there-has-been-a-loss-of-funds-414b99969c29

## Lessons Learned

1. **Never trust caller-supplied contract addresses as if they were protocol-registered entities.** Any function that accepts an external address and treats it as a first-class internal component (a Jar, a vault, a pool) must validate that address against an authoritative on-chain registry before acting on its return values.
2. **Avoid `delegatecall` with attacker-influenced calldata, even against "approved" targets.** Approving a target's *address* is not the same as approving every possible call that address can be tricked into making; `delegatecall` collapses the trust boundary between the calling contract and the target's logic.
3. **New functionality added to already-audited contracts needs its own dedicated audit.** The vulnerability was introduced when `swapExactJarForJar()` was added in a later version; incremental feature additions to security-critical contracts carry the same risk as the original code and should not be treated as low-risk changes.

The Rari security-upgrade report describes the earlier Fuse issue as **cross-asset reentrancy**, caused by the state not being fully updated before ETH was transferred. :contentReference[oaicite:11]{index=11}

---

# `sources/official-analysis.md`

```md
# Official Analysis

## Rari Capital Fuse Exploit Post-Mortem

On 30 April 2022, seven Fuse pools were exploited.

The Rari Capital post-mortem identifies the ETH borrowing path as the critical component.

The vulnerable implementation used `call.value()` to transfer ETH.

Because this allowed arbitrary code execution in the recipient's fallback function, an attacker could re-enter Fuse while the original borrow operation was still executing.

## Affected Pools

- 8
- 18
- 27
- 127
- 144
- 146
- 156

## Security Response

Rari Capital paused borrowing after identifying the attack.

The team had previously implemented a pool-wide reentrancy protection mechanism in newer Fuse deployments, but the affected pools were using older implementations.

The incident resulted in approximately $80 million in losses.

## Important Distinction

The vulnerability belongs to the Rari Capital Fuse lending contracts.

Fei Protocol was affected because Fei/Tribe assets were deposited into affected Rari Fuse pools following the Fei-Rari merger.

The vulnerability was therefore not a flaw in the FEI token contract itself.
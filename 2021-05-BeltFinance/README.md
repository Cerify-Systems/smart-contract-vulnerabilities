# Belt Finance Hack — May 29, 2021

**Incident type:** Flash loan assisted share price manipulation via a faulty valuation assumption (Solidity)
**Protocol:** Belt Finance (multi strategy yield vault on Binance Smart Chain)
**Amount lost:** roughly 6.23 million BUSD in attacker profit across 8 repeated transactions, with a combined pool level loss of about 50 million BUSD once fees are included

## TL;DR
Belt Finance V2 ran a multi strategy vault for BUSD, spreading deposits across several yield strategies including Venus and Ellipsis. To keep things simple and cheap on gas, the vault calculated the value of one vault share using only the Ellipsis (3eps) strategy's pool state, under the assumption that all strategies stayed roughly balanced with each other. An attacker used a flash loan to deposit a huge amount into the most undersubscribed strategy (Venus), pushing it out of balance, then separately manipulated the Ellipsis pool by swapping BUSD for USDT. Because the vault's share price calculation only looked at the now distorted Ellipsis pool and assumed everything else matched it, the vault believed each share was worth far more than it actually was. The attacker then withdrew from the Venus strategy at this inflated valuation, walking away with more BUSD than they had deposited. They repeated this eight times in a single wave of transactions.

## Folder guide
| File | What it covers |
|---|---|
| `summary.md` | Quick reference: when, where, why, the fix |
| `exploit.md` | Step by step mechanics of the flash loan and valuation manipulation |
| `fix.md` | What the team changed and the broader lesson on price oracle design |
| `contracts/` | Belt Finance's publicly available V1 contract architecture, included for context on the vault and strategy pattern the V2 exploit built on |
| `writeups/sources-index.md` | Sources referenced, with links |

## Vulnerable logic, at a glance
The vault's share valuation function derived the value of the entire multi strategy vault from a single strategy's pool state (Ellipsis 3eps), rather than checking each underlying strategy's actual balance independently. That single faulty assumption, that one pool's state can represent the value of every other strategy, is the entire root cause.

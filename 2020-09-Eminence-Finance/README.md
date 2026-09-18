# Eminence Finance Exploit — September 2020

## Incident

- Date: 29 September 2020
- Protocol: Eminence Finance
- Chain: Ethereum
- Main Asset: EMN
- Loss: Approximately $15 million
- Returned: Approximately $8 million
- Vulnerability: Bonding Curve / Economic Accounting Flaw
- Attack Technique: Flash Loan + Cross-Token Accounting Manipulation

## Summary

Eminence Finance was an unfinished DeFi gaming project whose smart
contracts were deployed to Ethereum mainnet for testing.

After the contracts became publicly known, users deposited approximately
$15 million into the system.

An attacker used a flash loan to exploit the interaction between the
EMN bonding curve and Eminence's secondary currencies.

The attacker first used DAI to mint EMN.

The EMN was then used to purchase a secondary Eminence currency.

This operation burned EMN.

The change in EMN supply altered the bonding-curve economics.

The attacker then sold the remaining EMN for DAI.

The process was repeated within the same transaction.

The resulting imbalance allowed the attacker to withdraw substantially
more DAI than was initially used.

## Attack Flow

```text
Flash Loan DAI
      |
      v
Mint EMN
      |
      v
Buy secondary Eminence token
      |
      v
EMN burned
      |
      v
EMN supply / reserve relationship changes
      |
      v
Sell remaining EMN
      |
      v
Receive DAI
      |
      v
Repeat
      |
      v
Repay flash loan
      |
      v
Remaining DAI = extracted value
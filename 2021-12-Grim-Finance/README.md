# Grim Finance Exploit — December 2021
## Incident

Grim Finance was exploited on Fantom on December 18, 2021 through a reentrancy vulnerability in the `GrimBoostVault` deposit path. The vault allowed the caller to supply an arbitrary token address to `depositFor()`. The vault then called `safeTransferFrom()` on that user-controlled token before calculating and minting the vault shares. A malicious token contract could therefore call `depositFor()` again while the original call was still executing. The nested calls observed the same stale pre-deposit pool balance and caused the vault to mint substantially more GB share tokens than the attacker had actually deposited. The attacker then withdrew the inflated shares for more underlying LP tokens and converted the LP tokens back into the borrowed assets. The incident affected multiple Grim vaults and was reported at approximately $30 million. Rekt's reconstruction documents the recursive `depositFor()` path and the use of a malicious token contract. 
## Vulnerable contract
The primary vulnerable contract is `GrimBoostVault`. The historical affected vault address documented by public exploit databases is `0x660184CE...4136BF`; the exact deployed vault/source should be checked against the specific affected pool when reproducing an individual attack. The vulnerability was in the `depositFor()` logic itself, not in the attacker's malicious token contract.
The exploit-relevant function had the following structure:
```solidity
function depositFor(uint _amount, address user) public {
    uint256 _pool = balance();
    IERC20(lpToken).safeTransferFrom(msg.sender, address(this), _amount);
    earn();
    uint256 _after = balance();
    _amount = _after.sub(_pool);
    uint256 shares = 0;
    if (totalSupply() == 0) {
        shares = _amount;
    } else {
        shares = (_amount.mul(totalSupply())).div(_pool);
    }
    _mint(user, shares);
}
```
The critical issue was that the token used by the vault could be controlled by the caller and the external `safeTransferFrom()` happened before `_mint()`. The historical analysis by Knownsec explicitly identifies `depositFor()` and the user-controlled token address as the root of the attack. 

## Attack mechanism
The attacker created a malicious token contract whose transfer function re-entered `GrimBoostVault.depositFor()`. The first call calculated `_pool` before the transfer. During `safeTransferFrom()`, the malicious token called `depositFor()` recursively several times. Each nested invocation used a stale pool value and eventually the final legitimate LP transfer increased the vault balance. When the calls unwound, the resulting balance difference was used repeatedly to mint GB shares. The attacker therefore received more vault shares than the amount of real LP tokens supplied justified.
The attacker then called the vault withdrawal path to redeem the inflated GB shares for SPIRIT-LP tokens. The LP tokens were removed from the underlying SpiritSwap pool, producing the original assets plus the excess created by the accounting manipulation. A flash loan was used to provide the initial WFTM/BTC liquidity in the documented attack sequence, but the core protocol vulnerability was the reentrancy and arbitrary-token input in `depositFor()`. 


## Impact
Approximately $30 million was reported stolen. Grim paused its vaults and later removed the exploited `depositFor()` function, added a kill-switch/sentinel mechanism, and introduced additional monitoring. 


## Folder contents
```text
2021-12-Grim-Finance/
├── contracts/
│   ├── GrimBoostVault_vulnerable.sol
├── README.md
├── summary.md
├── exploit.md
├── fix.md
└── writeups/
    ├── aftermath.md
    └── sources.md
```

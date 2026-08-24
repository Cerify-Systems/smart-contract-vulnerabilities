// Grim Finance GrimBoostVault — exploit-relevant historical logic
// Incident: December 18, 2021
// Vulnerability: reentrancy through caller-controlled token + stale pool accounting
//
// Historical source logic reproduced from:
// https://medium.com/@Knownsec_Blockchain_Lab/knownsec-blockchain-lab-grim-finance-flash-loan-security-incident-analysis-f613cd137144
// https://rekt.news/grim-finance-rekt
//
// This file intentionally contains the exploit-relevant depositFor() logic.
// It is not represented as the complete multi-file verified deployment.

pragma solidity 0.6.12;

interface IERC20 {
    function safeTransferFrom(address from, address to, uint256 amount) external;
}

contract GrimBoostVaultVulnerable {
    address public lpToken;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function balance() public view returns (uint256) {
        return IERC20(lpToken).balanceOf(address(this));
    }

    function earn() internal virtual {}

    function _mint(address user, uint256 shares) internal {
        totalSupply += shares;
        balanceOf[user] += shares;
    }

    // Historical vulnerable logic.
    // The original Grim implementation accepted an arbitrary token address
    // through the deposit path and made an external token call before
    // minting shares.
    function depositFor(uint256 _amount, address user) public {
        uint256 _pool = balance();

        IERC20(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        earn();

        uint256 _after = balance();
        _amount = _after - _pool;

        uint256 shares = 0;
        if (totalSupply == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply) / _pool;
        }

        _mint(user, shares);
    }
}

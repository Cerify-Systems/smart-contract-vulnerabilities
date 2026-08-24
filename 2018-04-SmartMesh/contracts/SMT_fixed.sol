// SPDX-License-Identifier: MIT
pragma solidity ^0.4.18;

/*
 * Patched version of SMT.sol using checked arithmetic (SafeMath pattern), matching the
 * remediation described in ../fix.md. Provided for comparison against the vulnerable
 * original in SMT.sol.
 */

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }
}

contract SMTFixed {
    using SafeMath for uint256;

    string public name = "SmartMesh Token";
    string public symbol = "SMT";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) balances;
    mapping(address => uint256) nonces;

    event Transfer(address indexed from, address indexed to, uint256 value);

    modifier transferAllowed(address _from) {
        _;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    function transferProxy(address _from, address _to, uint256 _value, uint256 _feeSmt,
        uint8 _v, bytes32 _r, bytes32 _s)
        public transferAllowed(_from) returns (bool)
    {
        // FIX: checked addition reverts on overflow instead of wrapping to 0.
        uint256 total = _value.add(_feeSmt);
        require(balances[_from] >= total, "insufficient balance");

        uint256 nonce = nonces[_from];
        bytes32 h = keccak256(abi.encodePacked(_from, _to, _value, _feeSmt, nonce));
        require(_from == ecrecover(h, _v, _r, _s), "invalid signature");

        balances[_to] = balances[_to].add(_value);
        balances[msg.sender] = balances[msg.sender].add(_feeSmt);
        balances[_from] = balances[_from].sub(total);
        nonces[_from] = nonce + 1;

        emit Transfer(_from, _to, _value);
        emit Transfer(_from, msg.sender, _feeSmt);
        return true;
    }
}

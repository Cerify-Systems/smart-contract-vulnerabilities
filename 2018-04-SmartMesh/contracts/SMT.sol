// SPDX-License-Identifier: MIT
pragma solidity ^0.4.18;

/*
 * SmartMesh (SMT) ERC-20 token contract.
 *
 * The `transferProxy()` function body below is reproduced from the verified source
 * published on Etherscan for the deployed SMT token contract
 * (0x55f93985431Fc9304077687a35A1BA103dC1e08), as it is the function containing the
 * "proxyOverflow" vulnerability (CVE-2018-10376) exploited on April 24-25, 2018.
 * Surrounding contract boilerplate (standard ERC-20 balances/allowances/events, the
 * `transferAllowed` modifier) is reconstructed for context and compilability, and is not
 * claimed to be a byte-for-byte copy of the full deployed source. See ../exploit.md for
 * a full walkthrough and ../writeups/sources.md for primary references (PeckShield).
 */

contract SMT {
    string public name = "SmartMesh Token";
    string public symbol = "SMT";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    // Versioning / distribution window used by the real contract's constructor.
    uint256 public allocateEndTime;

    // Nonce per address, used to prevent transferProxy replay.
    mapping(address => uint256) nonces;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier transferAllowed(address _from) {
        // Real contract gates proxy transfers on a distribution/lock-up window; simplified
        // here to a no-op passthrough for illustration.
        _;
    }

    function SMT() public {
        allocateEndTime = now + 1 days;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns (bool) {
        require(balances[msg.sender] >= _value);
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        Transfer(msg.sender, _to, _value);
        return true;
    }

    /*
     * Proxy transfer SmartMesh token.
     * When some users of the ethereum account has no ether,
     * he or she can authorize the agent for broadcast transactions, and agents may charge
     * agency fees.
     * @param _from
     * @param _to
     * @param _value
     * @param _feeSmt
     * @param _v
     * @param _r
     * @param _s
     *
     * VULNERABLE (CVE-2018-10376 / "proxyOverflow"): `_feeSmt + _value` and
     * `_value + _feeSmt` are raw uint256 additions with no overflow protection. An
     * attacker can choose _value and _feeSmt that sum to exactly 2^256, wrapping to 0,
     * which defeats the very first balance check below regardless of the sender's real
     * balance. See ../exploit.md for the full walkthrough.
     */
    function transferProxy(address _from, address _to, uint256 _value, uint256 _feeSmt,
        uint8 _v, bytes32 _r, bytes32 _s)
        public transferAllowed(_from) returns (bool)
    {
        if (balances[_from] < _feeSmt + _value) revert();

        uint256 nonce = nonces[_from];
        bytes32 h = keccak256(_from, _to, _value, _feeSmt, nonce);
        if (_from != ecrecover(h, _v, _r, _s)) revert();

        if (balances[_to] + _value < balances[_to] ||
            balances[msg.sender] + _feeSmt < balances[msg.sender]) revert();

        balances[_to] += _value;
        Transfer(_from, _to, _value);
        balances[msg.sender] += _feeSmt;
        Transfer(_from, msg.sender, _feeSmt);
        balances[_from] -= _value + _feeSmt;
        nonces[_from] = nonce + 1;
        return true;
    }
}

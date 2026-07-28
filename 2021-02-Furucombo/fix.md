# Fix

## Vulnerable Design

The Proxy contract delegates execution through the `_exec()` function:

```solidity
function _exec(address _to, bytes memory _data)
    internal
    returns (bytes memory result)
{
    require(_isValid(_to), "Invalid handler");

    assembly {
        let succeeded := delegatecall(
            sub(gas, 5000),
            _to,
            add(_data, 0x20),
            mload(_data),
            0,
            0
        )
        ...
    }
}
```

Although the contract verifies that the handler is registered, the protocol's overall design allowed malicious execution through the handler architecture. Once the attacker bypassed the intended trust assumptions, arbitrary logic was executed within the Proxy's storage context via `delegatecall`.

## Mitigation

Following the exploit, the Furucombo team paused the protocol and strengthened the security of the handler registration and execution process. The primary mitigation steps included:

- Improving validation of trusted handler contracts.
- Restricting the ability to execute untrusted or malicious handlers.
- Reviewing the registry mechanism to ensure only legitimate handlers could be used.
- Performing additional security audits before restoring protocol functionality.
- Compensating affected users through the protocol's recovery plan.


## Recommended Security Improvements

To prevent similar vulnerabilities, protocols using proxy architectures should:

### 1. Strengthen Handler Validation
Every delegated contract should undergo strict verification before being approved by the registry. Validation should include ownership checks, bytecode verification, and continuous monitoring.

### 2. Minimize Delegatecall Usage
`delegatecall` executes external code using the caller's storage, making it one of Solidity's most dangerous operations. Where possible, use normal `call` instead of `delegatecall`.

### 3. Principle of Least Privilege
Handlers should receive only the minimum permissions necessary to perform their intended operations. Avoid granting broad token approvals whenever possible.

### 4. Continuous Security Audits
Complex proxy systems require regular audits whenever new handlers or protocol integrations are introduced.

### 5. Comprehensive Testing

Security testing should include:

- Integration testing
- Fuzz testing
- Malicious handler simulations
- Delegatecall abuse scenarios
- Access-control verification

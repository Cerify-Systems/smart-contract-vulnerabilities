// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title HolographDeployer
 * @notice Deterministic contract deployment system using CREATE2
 * @dev Enables consistent addresses across chains using CREATE2
 *
 * Key features:
 * - CREATE2 deterministic deployment
 * - Salt validation (first 20 bytes must match sender)
 * - Deploy + initialize in one transaction
 * - Signed deployment support for gasless transactions
 * - Security against griefing attacks
 */
contract HolographDeployer is Ownable, EIP712 {
    using ECDSA for bytes32;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */
    event ContractDeployed(address indexed deployed, address indexed deployer, bytes32 salt, bytes32 creationCodeHash);

    event ContractDeployedAndInitialized(
        address indexed deployed, address indexed deployer, bytes32 salt, bytes32 creationCodeHash, bytes initData
    );

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */
    error InvalidSalt();
    error DeploymentFailed();
    error InitializationFailed();
    error AddressMismatch();
    error PreDeploymentAddressMismatch(address expected, address computed);
    error PostDeploymentAddressMismatch(address expected, address actual);
    error ContractAlreadyDeployed();
    error InvalidSignature();
    error SignatureExpired();

    /* -------------------------------------------------------------------------- */
    /*                                  Storage                                   */
    /* -------------------------------------------------------------------------- */
    /// @notice Mapping to track used nonces for signed deployments
    mapping(address => uint256) public deploymentNonces;

    /// @notice EIP-712 typehash for signed deployments
    bytes32 public constant DEPLOY_TYPEHASH =
        keccak256("Deploy(bytes32 creationCodeHash,bytes32 salt,uint256 nonce,uint256 deadline)");

    /* -------------------------------------------------------------------------- */
    /*                               Constructor                                  */
    /* -------------------------------------------------------------------------- */
    constructor() EIP712("HolographDeployer", "1") Ownable(msg.sender) {}

    /* -------------------------------------------------------------------------- */
    /*                            Deployment Functions                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Deploy a contract using CREATE2
     * @param creationCode The contract creation code (bytecode + constructor args)
     * @param salt The salt for CREATE2 deployment (first 20 bytes must match msg.sender)
     * @return deployed The address of the deployed contract
     */
    function deploy(bytes memory creationCode, bytes32 salt) public returns (address deployed) {
        // Validate salt - first 20 bytes must match sender
        if (address(bytes20(salt)) != msg.sender) {
            revert InvalidSalt();
        }

        deployed = _deploy(creationCode, salt);

        emit ContractDeployed(deployed, msg.sender, salt, keccak256(creationCode));
    }

    /**
     * @notice Deploy and initialize a contract in one transaction
     * @param creationCode The contract creation code
     * @param salt The salt for CREATE2 deployment
     * @param initData The initialization calldata
     * @return deployed The address of the deployed contract
     */
    function deployAndCall(bytes memory creationCode, bytes32 salt, bytes memory initData)
        public
        returns (address deployed)
    {
        // Validate salt
        if (address(bytes20(salt)) != msg.sender) {
            revert InvalidSalt();
        }

        deployed = _deploy(creationCode, salt);

        // Initialize the contract
        if (initData.length > 0) {
            (bool success,) = deployed.call(initData);
            if (!success) {
                revert InitializationFailed();
            }
        }

        emit ContractDeployedAndInitialized(deployed, msg.sender, salt, keccak256(creationCode), initData);
    }

    /**
     * @notice Deploy and validate a contract address matches expected
     * @param creationCode The contract creation code
     * @param salt The salt for CREATE2 deployment
     * @param expectedAddress The expected deployed address for validation
     * @return deployed The address of the deployed contract
     */
    function safeCreate2(bytes memory creationCode, bytes32 salt, address expectedAddress)
        public
        returns (address deployed)
    {
        // Pre-deployment validation
        address computedAddress = computeAddress(creationCode, salt);
        if (computedAddress != expectedAddress) {
            revert PreDeploymentAddressMismatch(expectedAddress, computedAddress);
        }

        // Deploy using standard deploy function
        deployed = deploy(creationCode, salt);

        // Post-deployment validation (should match pre-validation, but extra safety)
        if (deployed != expectedAddress) {
            revert PostDeploymentAddressMismatch(expectedAddress, deployed);
        }
    }

    /**
     * @notice Deploy, validate address, and initialize in one transaction
     * @param creationCode The contract creation code
     * @param salt The salt for CREATE2 deployment
     * @param expectedAddress The expected deployed address for validation
     * @param initData The initialization calldata
     * @return deployed The address of the deployed contract
     */
    function safeCreate2AndCall(bytes memory creationCode, bytes32 salt, address expectedAddress, bytes memory initData)
        public
        returns (address deployed)
    {
        // Pre-deployment validation
        address computedAddress = computeAddress(creationCode, salt);
        if (computedAddress != expectedAddress) {
            revert PreDeploymentAddressMismatch(expectedAddress, computedAddress);
        }

        // Deploy using deployAndCall function
        deployed = deployAndCall(creationCode, salt, initData);

        // Post-deployment validation (should match pre-validation, but extra safety)
        if (deployed != expectedAddress) {
            revert PostDeploymentAddressMismatch(expectedAddress, deployed);
        }
    }

    /**
     * @notice Deploy using a signature (for gasless/meta-transactions)
     * @param creationCode The contract creation code
     * @param salt The salt for CREATE2 deployment
     * @param deadline Signature expiration timestamp
     * @param signature The deployer's signature
     * @return deployed The address of the deployed contract
     */
    function deployWithSignature(bytes memory creationCode, bytes32 salt, uint256 deadline, bytes memory signature)
        public
        returns (address deployed)
    {
        if (block.timestamp > deadline) {
            revert SignatureExpired();
        }

        address signer = address(bytes20(salt));
        uint256 nonce = deploymentNonces[signer];

        // Verify signature
        bytes32 structHash = keccak256(abi.encode(DEPLOY_TYPEHASH, keccak256(creationCode), salt, nonce, deadline));

        bytes32 hash = _hashTypedDataV4(structHash);
        address recoveredSigner = hash.recover(signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }

        // Increment nonce
        deploymentNonces[signer]++;

        // Deploy
        deployed = _deploy(creationCode, salt);

        emit ContractDeployed(deployed, signer, salt, keccak256(creationCode));
    }

    /**
     * @notice Compute the CREATE2 address for a deployment
     * @param creationCode The contract creation code
     * @param salt The salt for CREATE2 deployment
     * @return The computed address
     */
    function computeAddress(bytes memory creationCode, bytes32 salt) public view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode)))))
        );
    }

    /**
     * @notice Verify a deployment matches expected parameters
     * @param deployed The deployed contract address
     * @param creationCode The expected creation code
     * @param salt The expected salt
     * @return True if the deployment matches
     */
    function verifyDeployment(address deployed, bytes memory creationCode, bytes32 salt) public view returns (bool) {
        return deployed == computeAddress(creationCode, salt) && deployed.code.length > 0;
    }

    /**
     * @notice Verify that a deployed address matches the expected address
     * @param expected The expected address
     * @param actual The actual deployed address
     * @dev Reverts with PostDeploymentAddressMismatch if addresses don't match
     */
    function verifyDeploymentAddress(address expected, address actual) public pure {
        if (expected != actual) {
            revert PostDeploymentAddressMismatch(expected, actual);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           Internal Functions                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Internal function to deploy using CREATE2
     * @param creationCode The contract creation code
     * @param salt The salt for CREATE2 deployment
     * @return deployed The deployed contract address
     */
    function _deploy(bytes memory creationCode, bytes32 salt) internal returns (address deployed) {
        // Check if already deployed
        address predicted = computeAddress(creationCode, salt);
        if (predicted.code.length > 0) {
            revert ContractAlreadyDeployed();
        }

        assembly {
            deployed := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }

        if (deployed == address(0)) {
            revert DeploymentFailed();
        }

        if (deployed != predicted) {
            revert AddressMismatch();
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @notice HolographBridge is temporarily out of scope and commented out.
 * @dev This contract will be re-enabled when OFT (Omnichain Fungible Token)
 *      support is implemented in a future version. The bridge handles cross-chain
 *      token expansion and coordination via LayerZero.
 *
 * IMPORTANT: We are NOT removing all bridging from the protocol. The FeeRouter
 * still maintains full LayerZero support for bridging Doppler integrator fees
 * from Base to Ethereum. Only token bridging is being deferred to a future version.
 */

/*
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "../lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroReceiver.sol";
import "../lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/libs/ExecutorOptions.sol";
import "./interfaces/IHolographBridge.sol";
import "./interfaces/IHolographFactory.sol";
import "./HolographERC20.sol";
import "./structs/BridgeStructs.sol";

**
 * @title HolographBridge
 * @notice Cross-chain expansion coordinator for HolographERC20 tokens using LayerZero V2
 * @dev Handles token deployment to new chains with automatic peer configuration
 * 
 * SECURITY NOTE - tx.origin Usage:
 * This contract uses tx.origin alongside msg.sender for creator authorization in the Doppler Airlock integration.
 * This is intentionally designed and secure for our specific use case:
 * 
 * 1. CONTEXT: Doppler Airlock owns all tokens deployed through it, so msg.sender authorization alone is insufficient
 *    to identify the actual token creator who should have cross-chain expansion privileges.
 * 
 * 2. PURPOSE: tx.origin tracks the original transaction initiator (token creator) through the call chain:
 *    User -> DopplerAirlock.createToken() -> HolographFactory.create() -> HolographBridge.expandToChain()
 * 
 * 3. SECURITY CONSIDERATIONS:
 *    - We check BOTH msg.sender AND tx.origin, requiring at least one to be the registered creator
 *    - This prevents unauthorized expansions while allowing legitimate ones through proxy contracts
 *    - The creator is established at token creation time and stored in HolographFactory
 *    - tx.origin cannot be spoofed by malicious contracts in the call chain
 * 
 * 4. GASLESS TRANSACTION PROTECTION:
 *    - Even with gasless transactions (meta-transactions), tx.origin represents the actual signer
 *    - Only the original token creator can authorize cross-chain expansions
 *    - Relayers cannot gain unauthorized access to token expansion functions
 * 
 * 5. PHISHING RESISTANCE:
 *    - Users must explicitly call expansion functions; they cannot be tricked into
 *      calling malicious contracts that would abuse tx.origin
 *    - The authorization check is for expansion privileges, not fund transfers
 * 
 * This pattern is specifically justified for Doppler Airlock integration where traditional
 * msg.sender authorization is insufficient due to the proxy ownership model.
 * 
 * @author Holograph Protocol
 *
contract HolographBridge is IHolographBridge, ILayerZeroReceiver, Ownable, Pausable, ReentrancyGuard {

    // ========== Contract code omitted - will be restored in a future version ==========
    // Full implementation includes:
    // - Cross-chain token expansion via expandToChain()
    // - LayerZero message handling for token deployments
    // - Chain configuration and peer management
    // - Creator authorization with tx.origin support
    // - Emergency pause functionality
    
}
*/

# Official Postmortem

## Summary

The King of the Ether Throne incident highlighted one of the earliest payment handling issues in Ethereum smart contracts. The game rewarded the previous monarch by automatically sending Ether whenever a new player claimed the throne. However, this assumption failed when the previous monarch was a smart contract that could not successfully receive Ether through the payment mechanism used by the game.

As a result, the automatic compensation failed even though the throne claim itself succeeded. This incident demonstrated that smart contracts should never assume external Ether transfers will always succeed.

## Root Cause

The original contract relied on automatically sending compensation to the previous monarch during the throne claim process.

When the recipient was a contract whose fallback function rejected the transfer or required more gas than provided, the payment could not be completed successfully.

The incident exposed the risks of depending on immediate external Ether transfers during critical contract execution.

## Resolution

The payment mechanism was redesigned so that failed compensation payments were recorded inside the contract instead of blocking the game.

If compensation could not be delivered immediately, the amount was stored internally and could later be withdrawn by the recipient using a dedicated withdrawal function.

This approach became an early example of the Pull over Push payment pattern, which is now considered a best practice in Solidity development.

## Source

https://www.kingoftheether.com/postmortem.html
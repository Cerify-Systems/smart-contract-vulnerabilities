# OpenZeppelin Analysis

Summary:

OpenZeppelin explains that the vulnerability occurred because the WalletLibrary contract was left uninitialized.

After initialization by an external account, privileged functions became available, allowing the library contract to be destroyed using selfdestruct.

Reference:

https://www.openzeppelin.com/news/parity-wallet-hack-reloaded
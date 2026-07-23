# Parity Technologies Postmortem

Summary:

- Shared WalletLibrary contract remained uninitialized.
- A user initialized the library and became owner.
- The owner invoked kill(), destroying the library.
- All proxy wallets depending on the library became unusable.

Reference:

https://medium.com/paritytech/a-postmortem-on-the-parity-multi-sig-library-self-destruct-63daca3a4cf
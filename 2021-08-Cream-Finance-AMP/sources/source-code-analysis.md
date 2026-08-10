# Source Code Analysis

## Vulnerable Component

The vulnerability occurred in C.R.E.A.M. Finance's lending implementation, specifically the borrowing flow used by the affected markets.

The critical operation was the transfer of borrowed tokens before the corresponding borrowing state had been fully updated.

## Vulnerable Execution Flow

The vulnerable sequence can be simplified as:

```solidity
doTransferOut(borrower, borrowAmount);

// State updates occur after the external transfer
accountBorrows[borrower].principal = vars.accountBorrowsNew;
accountBorrows[borrower].interestIndex = borrowIndex;
totalBorrows = vars.totalBorrowsNew;
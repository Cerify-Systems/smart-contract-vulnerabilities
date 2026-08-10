# CREAM Finance AMP Reentrancy (2021)

## Overview

On August 31, 2021, C.R.E.A.M. Finance suffered a major exploit involving the integration of the AMP token into its lending protocol.

The vulnerability was caused by reentrancy through AMP's ERC-777-style token transfer callback. CREAM's lending implementation performed an external token transfer before updating the corresponding borrowing state, allowing an attacker to re-enter the borrowing function while the original borrow operation was still in progress.

## Background

AMP implements ERC-777 functionality that allows token transfers to trigger a recipient callback through `tokensReceived()`.

CREAM integrated AMP as a collateral and lending asset. The lending protocol did not adequately account for the callback behavior during its borrowing process.

The attacker exploited this interaction to repeatedly enter the borrowing logic before the protocol's internal accounting was updated.

## Root Cause

The vulnerable execution sequence was approximately:

```solidity
doTransferOut(borrower, borrowAmount);

// Accounting updated after the external call
accountBorrows[borrower].principal = vars.accountBorrowsNew;
accountBorrows[borrower].interestIndex = borrowIndex;
totalBorrows = vars.totalBorrowsNew;
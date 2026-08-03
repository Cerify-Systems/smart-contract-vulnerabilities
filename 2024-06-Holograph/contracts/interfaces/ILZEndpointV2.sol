// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ILZEndpointV2 {
    function send(uint32 dstEid, bytes calldata payload, bytes calldata options) external payable;
}

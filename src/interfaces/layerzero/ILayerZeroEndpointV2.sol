// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev The fee quoted/charged for a LayerZero message.
struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

/// @dev Receipt returned by a LayerZero send().
struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

/// @title ILayerZeroEndpointV2
/// @notice Minimal interface for the LayerZero V2 endpoint. Only the pieces
///         used here: setting the OApp delegate and identifying the endpoint
///         (msg.sender check in lzCompose).
interface ILayerZeroEndpointV2 {
    function setDelegate(address _delegate) external;

    function eid() external view returns (uint32);
}

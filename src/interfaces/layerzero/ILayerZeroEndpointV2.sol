// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev Origin of an inbound LayerZero message.
struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

/// @dev Parameters for an outbound LayerZero message.
struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

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
/// @notice Minimal interface for the LayerZero V2 endpoint used for OApp
///         messaging (non-token report messages).
interface ILayerZeroEndpointV2 {
    function quote(
        MessagingParams calldata _params,
        address _sender
    ) external view returns (MessagingFee memory);

    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);

    function setDelegate(address _delegate) external;

    function eid() external view returns (uint32);
}

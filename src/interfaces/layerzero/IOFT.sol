// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev Token parameters for an OFT send() operation.
struct SendParam {
    uint32 dstEid; // Destination endpoint ID.
    bytes32 to; // Recipient address.
    uint256 amountLD; // Amount to send in local decimals.
    uint256 minAmountLD; // Minimum amount to receive in local decimals.
    bytes extraOptions; // Additional options.
    bytes composeMsg; // The composed message.
    bytes oftCmd; // The OFT command (unused in default OFTs).
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

/// @dev Receipt of an OFT send() operation.
struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
}

/// @title IOFT
/// @notice Minimal interface for LayerZero V2 OFT and OFT Adapter contracts.
interface IOFT {
    /// @notice The ERC20 token the OFT moves (the OFT itself for a native OFT).
    function token() external view returns (address);

    /// @notice Whether the OFT requires ERC20 approval to pull tokens.
    function approvalRequired() external view returns (bool);

    /// @notice 10 ** (localDecimals - sharedDecimals); amounts truncate to this.
    function decimalConversionRate() external view returns (uint256);

    /// @notice Decimals shared across the OFT mesh (amounts truncate to these).
    function sharedDecimals() external view returns (uint8);

    /// @notice Quote the messaging fee for a send() operation.
    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory);

    /// @notice Send tokens to a remote chain.
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory, OFTReceipt memory);

    /// @notice The peer OFT contract on a remote endpoint.
    function peers(uint32 _eid) external view returns (bytes32);
}

/// @title ILayerZeroComposer
/// @notice The receive side of a LayerZero V2 compose message. After an OFT
///         delivers tokens to a recipient, the endpoint calls lzCompose on
///         that recipient with the attached compose payload.
interface ILayerZeroComposer {
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}

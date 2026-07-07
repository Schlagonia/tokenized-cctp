// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev Struct representing token parameters for an OFT send() operation.
struct SendParam {
    uint32 dstEid; // Destination endpoint ID.
    bytes32 to; // Recipient address.
    uint256 amountLD; // Amount to send in local decimals.
    uint256 minAmountLD; // Minimum amount to send in local decimals.
    bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
    bytes composeMsg; // The composed message for the send() operation.
    bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
}

/// @dev Struct representing the messaging fee for an OFT send() operation.
struct MessagingFee {
    uint256 nativeFee; // Fee in native gas token.
    uint256 lzTokenFee; // Fee in ZRO token.
}

/// @dev Struct representing the receipt of an OFT send() operation.
struct OFTReceipt {
    uint256 amountSentLD; // Amount of tokens ACTUALLY debited from the sender in local decimals.
    uint256 amountReceivedLD; // Amount of tokens to be received on the remote side.
}

/// @dev Struct representing the receipt of a LayerZero message.
struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

/// @title IOFT
/// @notice Minimal interface for LayerZero V2 OFT and OFT Adapter contracts.
interface IOFT {
    /// @notice The address of the ERC20 token the OFT moves.
    /// @dev For a native OFT this is the OFT itself, for an adapter it is the wrapped token.
    function token() external view returns (address);

    /// @notice Whether the OFT requires ERC20 approval to pull tokens (adapter/lockbox case).
    function approvalRequired() external view returns (bool);

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

    /// @notice Rate used to convert between local and shared decimals.
    /// @dev 10 ** (localDecimals - sharedDecimals). Amounts are truncated to
    ///      this granularity ("dust removal") when sent.
    function decimalConversionRate() external view returns (uint256);
}

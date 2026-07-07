// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title OFTComposeMsgCodec
/// @notice Decoder for the compose message an OFT delivers to lzCompose.
/// @dev Vendored from LayerZero Labs (lz-evm-oapp-v2) to avoid pulling the
///      full dependency. Layout:
///      [0:8] nonce | [8:12] srcEid | [12:44] amountLD |
///      [44:76] composeFrom | [76:] composeMsg.
library OFTComposeMsgCodec {
    uint8 private constant NONCE_OFFSET = 8;
    uint8 private constant SRC_EID_OFFSET = 12;
    uint8 private constant AMOUNT_LD_OFFSET = 44;
    uint8 private constant COMPOSE_FROM_OFFSET = 76;

    /// @notice The nonce of the source message.
    function nonce(bytes calldata _msg) internal pure returns (uint64) {
        return uint64(bytes8(_msg[:NONCE_OFFSET]));
    }

    /// @notice The source LayerZero endpoint ID.
    function srcEid(bytes calldata _msg) internal pure returns (uint32) {
        return uint32(bytes4(_msg[NONCE_OFFSET:SRC_EID_OFFSET]));
    }

    /// @notice The amount delivered, in local decimals.
    function amountLD(bytes calldata _msg) internal pure returns (uint256) {
        return uint256(bytes32(_msg[SRC_EID_OFFSET:AMOUNT_LD_OFFSET]));
    }

    /// @notice The composer (sender) on the source chain, as bytes32.
    function composeFrom(bytes calldata _msg) internal pure returns (bytes32) {
        return bytes32(_msg[AMOUNT_LD_OFFSET:COMPOSE_FROM_OFFSET]);
    }

    /// @notice The attached compose payload.
    function composeMsg(
        bytes calldata _msg
    ) internal pure returns (bytes memory) {
        return _msg[COMPOSE_FROM_OFFSET:];
    }
}

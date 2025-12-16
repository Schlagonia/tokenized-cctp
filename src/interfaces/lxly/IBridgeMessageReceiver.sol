// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @title IBridgeMessageReceiver
/// @notice Interface for contracts that receive cross-chain messages via the LxLy bridge
/// @dev Implement this interface to receive messages from bridgeMessage() calls
interface IBridgeMessageReceiver {
    /// @notice Called by the bridge when a message is claimed
    /// @param originAddress The sender address on the origin network
    /// @param originNetwork The network ID where the message originated
    /// @param data The message payload
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable;
}

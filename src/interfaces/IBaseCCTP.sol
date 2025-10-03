// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IMessageHandlerV2} from "./circle/IMessageHandlerV2.sol";
import {ITokenMessenger} from "./circle/ITokenMessenger.sol";
import {IMessageTransmitter} from "./circle/IMessageTransmitter.sol";

/// @notice Interface for CCTP-specific message handler base contract
/// @dev Extends IMessageHandlerV2 with CCTP contract accessors
interface IBaseCCTP is IMessageHandlerV2 {
    /// @notice CCTP token messenger contract
    /// @return The token messenger address
    function TOKEN_MESSENGER() external view returns (ITokenMessenger);

    /// @notice CCTP message transmitter contract
    /// @return The message transmitter address
    function MESSAGE_TRANSMITTER() external view returns (IMessageTransmitter);
}

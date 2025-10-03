// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IMessageHandlerV2} from "./interfaces/circle/IMessageHandlerV2.sol";
import {ITokenMessenger} from "./interfaces/circle/ITokenMessenger.sol";
import {IMessageTransmitter} from "./interfaces/circle/IMessageTransmitter.sol";

/// @notice CCTP-specific message handler base contract
/// @dev Validates CCTP messages and routes to implementations
abstract contract BaseCCTP is IMessageHandlerV2 {
    /// @notice CCTP token messenger contract
    ITokenMessenger public immutable TOKEN_MESSENGER;

    /// @notice CCTP message transmitter contract
    IMessageTransmitter public immutable MESSAGE_TRANSMITTER;

    /// @notice The threshold at which (and above) messages are considered finalized
    uint32 internal constant FINALITY_THRESHOLD_FINALIZED = 2_000;

    constructor(address _tokenMessenger, address _messageTransmitter) {
        require(
            _tokenMessenger != address(0) && _messageTransmitter != address(0),
            "ZeroAddress"
        );

        TOKEN_MESSENGER = ITokenMessenger(_tokenMessenger);
        MESSAGE_TRANSMITTER = IMessageTransmitter(_messageTransmitter);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _addressToBytes32(
        address _address
    ) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }
}

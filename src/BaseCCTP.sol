// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IMessageHandlerV2} from "./interfaces/circle/IMessageHandlerV2.sol";
import {ITokenMessenger} from "./interfaces/circle/ITokenMessenger.sol";
import {IMessageTransmitter} from "./interfaces/circle/IMessageTransmitter.sol";

abstract contract BaseCCTP is IMessageHandlerV2 {
    uint32 public immutable REMOTE_DOMAIN;

    address public immutable REMOTE_COUNTERPART;

    ITokenMessenger public immutable TOKEN_MESSENGER;

    IMessageTransmitter public immutable MESSAGE_TRANSMITTER;

    // The threshold at which (and above) messages are considered finalized.
    uint32 internal constant FINALITY_THRESHOLD_FINALIZED = 2000;

    uint256 public nextRequestId;

    mapping(uint256 => bool) public messageProcessed;

    constructor(
        address _tokenMessenger,
        address _messageTransmitter,
        uint32 _remoteDomain,
        address _remoteCounterpart
    ) {
        require(
            _tokenMessenger != address(0) &&
                _messageTransmitter != address(0) &&
                _remoteCounterpart != address(0),
            "ZeroAddress"
        );
        require(_remoteDomain != 0, "InvalidDomain");

        REMOTE_DOMAIN = _remoteDomain;
        REMOTE_COUNTERPART = _remoteCounterpart;
        TOKEN_MESSENGER = ITokenMessenger(_tokenMessenger);
        MESSAGE_TRANSMITTER = IMessageTransmitter(_messageTransmitter);

        // Start ID's at 1 so ordered checks work.
        nextRequestId = 1;
        messageProcessed[0] = true;
    }

    function handleReceiveFinalizedMessage(
        uint32 _sourceDomain,
        bytes32 _sender,
        uint32 _finalityThresholdExecuted,
        bytes calldata _messageBody
    ) external virtual override returns (bool) {
        require(
            msg.sender == address(MESSAGE_TRANSMITTER),
            "InvalidTransmitter"
        );
        require(_sourceDomain == REMOTE_DOMAIN, "InvalidDomain");
        require(
            _sender == _addressToBytes32(REMOTE_COUNTERPART),
            "InvalidSender"
        );
        require(_messageBody.length > 0, "EmptyMessage");
        require(
            _finalityThresholdExecuted >= FINALITY_THRESHOLD_FINALIZED,
            "InvalidFinalityThreshold"
        );

        (uint256 requestId, int256 amount) = abi.decode(
            _messageBody,
            (uint256, int256)
        );

        require(!messageProcessed[requestId], "MessageAlreadyProcessed");
        require(
            messageProcessed[requestId - 1],
            "PreviousMessageNotProccessed"
        );

        _receiveMessage(amount);

        messageProcessed[requestId] = true;

        return true;
    }

    function _receiveMessage(int256 amount) internal virtual;

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _addressToBytes32(
        address _address
    ) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Origin} from "./ILayerZeroEndpointV2.sol";

/// @title ILayerZeroReceiver
/// @notice The receive side of a LayerZero V2 OApp. The endpoint calls
///         lzReceive to deliver a verified message.
interface ILayerZeroReceiver {
    function allowInitializePath(
        Origin calldata _origin
    ) external view returns (bool);

    function nextNonce(
        uint32 _srcEid,
        bytes32 _sender
    ) external view returns (uint64);

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}

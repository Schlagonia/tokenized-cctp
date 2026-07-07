// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

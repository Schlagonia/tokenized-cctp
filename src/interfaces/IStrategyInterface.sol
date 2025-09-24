// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

interface IStrategyInterface is IBaseHealthCheck {
    function remoteAssets() external view returns (uint256);

    function reported(uint64 _requestId) external view returns (bool);

    function requestRemoteWithdrawal(
        uint256 _assets
    ) external returns (uint64 _requestId);

    function handleReceiveMessage(
        uint32 _sourceDomain,
        bytes32 _sender,
        bytes calldata _messageBody
    ) external;
}

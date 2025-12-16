// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IPolygonZkEVMBridgeV2} from "../interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IBridgeMessageReceiver} from "../interfaces/lxly/IBridgeMessageReceiver.sol";

/// @notice LxLy bridge base contract for cross-chain strategies
/// @dev Provides common bridge interface and validation for Katana/Agglayer integration
abstract contract BaseLxLy is IBridgeMessageReceiver {
    /// @notice The LxLy Unified Bridge contract
    IPolygonZkEVMBridgeV2 public immutable LXLY_BRIDGE;

    /// @notice The network ID of the chain this contract is deployed on
    uint32 public immutable LOCAL_NETWORK_ID;

    constructor(address _bridge) {
        require(_bridge != address(0), "ZeroAddress");

        LXLY_BRIDGE = IPolygonZkEVMBridgeV2(_bridge);
        LOCAL_NETWORK_ID = LXLY_BRIDGE.networkID();
    }

    /// @notice Get the wrapped token address for a given origin token
    /// @param originNetwork The network ID where the token originated
    /// @param originTokenAddress The token address on the origin network
    /// @return The wrapped token address on this network
    function getWrappedToken(
        uint32 originNetwork,
        address originTokenAddress
    ) public view returns (address) {
        return
            LXLY_BRIDGE.getTokenWrappedAddress(
                originNetwork,
                originTokenAddress
            );
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "./IBaseCrossChain.sol";
import {IVaultBridgeToken} from "./lxly/IVaultBridgeToken.sol";
import {IPolygonZkEVMBridgeV2} from "./lxly/IPolygonZkEVMBridgeV2.sol";

/// @title IKatanaStrategy
/// @notice Interface for the KatanaStrategy contract
/// @dev Combines IBaseCrossChain (which includes IBaseHealthCheck with all TokenizedStrategy functions)
///      with Katana-specific and LxLy bridge functions
interface IKatanaStrategy is IBaseCrossChain {
    /*//////////////////////////////////////////////////////////////
                        KATANA-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The VaultBridgeToken contract for wrapping and bridging
    /// @return The VaultBridgeToken interface
    function VB_TOKEN() external view returns (IVaultBridgeToken);

    /// @notice Redeem any vbToken held by the strategy for underlying asset
    /// @dev Only callable by keepers
    function redeemVaultTokens() external;

    /// @notice Rescue tokens accidentally sent to this contract
    /// @param _token Token to rescue (cannot be the strategy asset)
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(address _token, address _to, uint256 _amount) external;

    /// @notice Total assets tracked on remote chain
    /// @return Amount of assets deployed remotely
    function remoteAssets() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        LXLY BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The LxLy Unified Bridge contract
    /// @return The bridge interface
    function LXLY_BRIDGE() external view returns (IPolygonZkEVMBridgeV2);

    /// @notice The network ID of the chain this contract is deployed on
    /// @return The local network ID
    function LOCAL_NETWORK_ID() external view returns (uint32);

    /// @notice Handle incoming bridge message from remote chain
    /// @dev Called by the bridge when a message is claimed
    /// @param originAddress The sender address on the origin network
    /// @param originNetwork The network ID where the message originated
    /// @param data The message payload (encoded totalAssets)
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable;
}

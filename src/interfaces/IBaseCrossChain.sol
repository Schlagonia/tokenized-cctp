// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

/// @notice Interface for cross-chain strategies on the origin chain
/// @dev Extends IBaseHealthCheck with cross-chain specific functionality
interface IBaseCrossChain is IBaseHealthCheck {
    event RemoteAssetsUpdated(uint256 indexed amount);

    /// @notice Remote chain identifier (can be domain ID, chain ID, etc.)
    /// @return The remote chain identifier
    function REMOTE_ID() external view returns (bytes32);

    /// @notice Remote chain ID.
    /// @return The remote chain ID
    function REMOTE_CHAIN_ID() external view returns (uint256);

    /// @notice Address of the remote strategy counterpart
    /// @return The remote counterpart address
    function REMOTE_COUNTERPART() external view returns (address);

    /// @notice Address allowed to deposit into this strategy
    /// @return The depositer address
    function DEPOSITER() external view returns (address);

    /// @notice Total assets tracked on remote chain
    /// @return Amount of assets deployed remotely
    function remoteAssets() external view returns (uint256);

    /// @notice Timestamp watermark for remote asset updates
    /// @return Latest accepted report or local deploy timestamp
    function lastRemoteAssetsReport() external view returns (uint256);

    /// @notice Loose strategy asset balance
    /// @return Balance of the strategy asset held locally
    function balanceOfAsset() external view returns (uint256);
}

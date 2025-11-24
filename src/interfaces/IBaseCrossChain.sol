// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

/// @notice Interface for cross-chain strategies on the origin chain
/// @dev Extends IBaseHealthCheck with cross-chain specific functionality
interface IBaseCrossChain is IBaseHealthCheck {
    /// @notice Remote chain identifier (can be domain ID, chain ID, etc.)
    /// @return The remote chain identifier
    function REMOTE_ID() external view returns (bytes32);

    /// @notice Address of the remote strategy counterpart
    /// @return The remote counterpart address
    function REMOTE_COUNTERPART() external view returns (address);

    /// @notice Address allowed to deposit into this strategy
    /// @return The depositer address
    function DEPOSITER() external view returns (address);

    /// @notice Tracks unreported profit/loss
    /// @return The unreported profit/loss
    function unreportedProfit() external view returns (int256);
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IGovernance} from "@periphery/interfaces/utils/IGovernance.sol";

/// @notice Interface for cross-chain strategies on remote chains
/// @dev Extends IGovernance with remote strategy specific functionality
interface IBaseRemoteStrategy is IGovernance {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a keeper's status is updated
    /// @param keeper The keeper address
    /// @param status The new keeper status
    event UpdatedKeeper(address indexed keeper, bool indexed status);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Remote chain identifier for the origin chain
    /// @return The remote chain identifier
    function REMOTE_ID() external view returns (bytes32);

    /// @notice Address of the origin strategy counterpart
    /// @return The remote counterpart address
    function REMOTE_COUNTERPART() external view returns (address);

    /// @notice The asset token for this strategy
    /// @return The asset token address
    function asset() external view returns (address);

    /// @notice The ERC4626 vault where assets are deployed
    /// @return The vault address
    function vault() external view returns (address);

    /// @notice Counter for ordering cross-chain messages
    /// @return The next request ID
    function nextRequestId() external view returns (uint256);

    /// @notice Tracks assets for profit/loss calculations
    /// @return The tracked assets amount
    function trackedAssets() external view returns (uint256);

    /// @notice Mapping to prevent message replay and enforce ordering
    /// @param requestId The request ID to check
    /// @return Whether the message has been processed
    function messageProcessed(uint256 requestId) external view returns (bool);

    /// @notice Addresses authorized to perform keeper operations
    /// @param keeper The address to check
    /// @return Whether the address is a keeper
    function keepers(address keeper) external view returns (bool);

    /// @notice Calculate total assets held (vault + loose)
    function totalAssets() external view returns (uint256);

    /// @notice Calculate assets deployed in vault
    function vaultAssets() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Send exposure report to origin chain
    /// @dev Calculates profit/loss and bridges message back
    /// @return reportProfit The profit/loss reported to the origin chain
    function sendReport() external returns (int256 reportProfit);

    /// @notice Process withdrawal request from origin chain
    /// @dev Withdraws from vault if needed and bridges tokens back
    /// @param _amount Amount to withdraw and bridge back
    function processWithdrawal(uint256 _amount) external;

    /// @notice Push loose funds into the vault
    /// @param _amount Amount to deposit into vault
    function pushFunds(uint256 _amount) external;

    /// @notice Pull funds from the vault
    /// @param _shares Amount of shares to redeem from vault
    function pullFunds(uint256 _shares) external;

    /// @notice Set keeper status for an address
    /// @param _address Address to update
    /// @param _allowed Whether address should have keeper privileges
    function setKeeper(address _address, bool _allowed) external;
}

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

    /// @notice Emitted when profit max unlock time is updated
    /// @param profitMaxUnlockTime The new profit max unlock time
    event UpdatedProfitMaxUnlockTime(uint256 indexed profitMaxUnlockTime);

    /// @notice Emitted when shutdown status is updated
    /// @param isShutdown The new shutdown status
    event UpdatedIsShutdown(bool indexed isShutdown);

    /// @notice Emitted when a report is sent
    /// @param reportProfit The profit/loss reported
    event Reported(int256 indexed reportProfit);

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

    /// @notice Assets deployed in the vault
    /// @return The deployed assets amount
    function deployedAssets() external view returns (uint256);

    /// @notice Maximum unlock time for profit distribution
    /// @return The profit max unlock time
    function profitMaxUnlockTime() external view returns (uint256);

    /// @notice Timestamp of last report
    /// @return The last report timestamp
    function lastReport() external view returns (uint256);

    /// @notice Whether the strategy is shutdown
    /// @return The shutdown status
    function isShutdown() external view returns (bool);

    /// @notice Addresses authorized to perform keeper operations
    /// @param keeper The address to check
    /// @return Whether the address is a keeper
    function keepers(address keeper) external view returns (bool);

    /// @notice Calculate total assets held (vault + loose)
    function totalAssets() external view returns (uint256);

    /// @notice Calculate value of assets deployed in vault
    function valueOfDeployedAssets() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Send exposure report to origin chain
    /// @dev Calculates profit/loss and bridges message back
    /// @return reportProfit The profit/loss reported to the origin chain
    function report() external returns (int256 reportProfit);

    /// @notice Deploy idle assets if conditions are met
    /// @dev Deposits idle assets into the vault
    function tend() external;

    /// @notice Check if tend should be called
    /// @return shouldTend Whether tend should be triggered
    /// @return reason Encoded reason for the trigger
    function tendTrigger()
        external
        view
        returns (bool shouldTend, bytes memory reason);

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

    /// @notice Set the auction address
    /// @param _auction The new auction address
    function setAuction(address _auction) external;

    /// @notice Set the profit max unlock time
    /// @param _profitMaxUnlockTime The new profit max unlock time
    function setProfitMaxUnlockTime(uint256 _profitMaxUnlockTime) external;

    /// @notice Set the shutdown status
    /// @param _isShutdown The new shutdown status
    function setIsShutdown(bool _isShutdown) external;
}

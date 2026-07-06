// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseRemoteStrategy} from "./IBaseRemoteStrategy.sol";
import {IBaseCCTP} from "./IBaseCCTP.sol";

/// @notice Interface for CCTP Remote Strategy on remote chains
/// @dev Combines remote strategy functionality with CCTP messaging
interface ICCTPRemoteStrategy is IBaseRemoteStrategy, IBaseCCTP {
    /// @notice The ERC4626 vault where assets are deployed
    /// @return The vault address
    function vault() external view returns (address);

    /// @notice Rescue tokens accidentally sent to this contract
    /// @param _token Token to rescue
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(address _token, address _to, uint256 _amount) external;
}

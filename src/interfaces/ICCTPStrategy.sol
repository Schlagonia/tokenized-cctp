// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "./IBaseCrossChain.sol";
import {IBaseCCTP} from "./IBaseCCTP.sol";

/// @notice Interface for CCTP Strategy on origin chain
/// @dev Combines cross-chain strategy functionality with CCTP messaging
interface ICCTPStrategy is IBaseCrossChain, IBaseCCTP {
    /// @notice Rescue tokens accidentally sent to this contract
    /// @param _token Token to rescue
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(address _token, address _to, uint256 _amount) external;
}

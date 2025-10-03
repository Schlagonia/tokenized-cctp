// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseRemoteStrategy} from "./IBaseRemoteStrategy.sol";
import {IBaseCCTP} from "./IBaseCCTP.sol";

/// @notice Interface for CCTP Remote Strategy on remote chains
/// @dev Combines remote strategy functionality with CCTP messaging
interface ICCTPRemoteStrategy is IBaseRemoteStrategy, IBaseCCTP {
    // All functionality inherited from IBaseRemoteStrategy and IBaseCCTP
    // No additional CCTP-specific functions beyond the base interfaces
}

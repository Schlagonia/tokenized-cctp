// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "./IBaseCrossChain.sol";
import {IBaseCCTP} from "./IBaseCCTP.sol";

/// @notice Interface for CCTP Strategy on origin chain
/// @dev Combines cross-chain strategy functionality with CCTP messaging
interface ICCTPStrategy is IBaseCrossChain, IBaseCCTP {
    // All functionality inherited from IBaseCrossChain and IBaseCCTP
    // No additional CCTP-specific functions beyond the base interfaces
}

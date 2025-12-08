// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @title ICoreWriter
/// @notice Interface for sending transactions to the HyperLiquid L1 (HyperCore)
/// @dev This precompile is available on HyperEVM at address 0x3333...3333
interface ICoreWriter {
    /// @notice Send a raw action to HyperCore L1
    /// @param data Encoded action data (version byte + action type + abi-encoded params)
    function sendRawAction(bytes calldata data) external;
}

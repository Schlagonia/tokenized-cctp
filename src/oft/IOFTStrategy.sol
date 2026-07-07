// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "../interfaces/IBaseCrossChain.sol";
import {IBaseRemoteStrategy} from "../interfaces/IBaseRemoteStrategy.sol";

/// @notice Shared surface of the OFT bridge base (BaseOFT).
interface IBaseOFT {
    /// @notice The OFT (or OFT adapter) that bridges the strategy asset.
    function OFT() external view returns (address);

    /// @notice The LayerZero endpoint (authenticates lzCompose callers).
    function ENDPOINT() external view returns (address);

    /// @notice LayerZero endpoint ID of the counterpart chain.
    function REMOTE_EID() external view returns (uint32);

    /// @notice Type-3 executor options attached to sends.
    function lzOptions() external view returns (bytes memory);

    /// @notice Receive a report attached to an OFT transfer (compose).
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;

    /// @notice Rescue ETH held for LayerZero fees.
    function rescueETH(address _to, uint256 _amount) external;
}

/// @title IOFTStrategy
/// @notice Interface for the origin OFTStrategy: a cross-chain strategy that
///         bridges its asset via a LayerZero OFT and ingests remote reports as
///         compose messages.
interface IOFTStrategy is IBaseCrossChain, IBaseOFT {
    /// @notice Rescue tokens accidentally sent to this contract.
    function rescue(address _token, address _to, uint256 _amount) external;
}

/// @title IOFTRemoteStrategy
/// @notice Interface for the remote OFTRemoteStrategy: receives its asset via
///         the OFT, deploys into an ERC4626 vault, and reports home over the
///         same OFT bridge.
interface IOFTRemoteStrategy is IBaseRemoteStrategy, IBaseOFT {
    /// @notice The ERC4626 vault assets are deployed into.
    function vault() external view returns (address);

    /// @notice Rescue tokens accidentally sent to this contract.
    function rescue(address _token, address _to, uint256 _amount) external;
}

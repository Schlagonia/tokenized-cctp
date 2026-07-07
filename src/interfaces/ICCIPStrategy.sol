// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "./IBaseCrossChain.sol";
import {IBaseRemoteStrategy} from "./IBaseRemoteStrategy.sol";
import {Client} from "./ccip/ICCIP.sol";

/// @notice Shared surface of the CCIP bridge base (BaseCCIP).
interface IBaseCCIP {
    /// @notice The CCIP router on this chain.
    function ROUTER() external view returns (address);

    /// @notice CCIP chain selector of the counterpart chain.
    function REMOTE_CHAIN_SELECTOR() external view returns (uint64);

    /// @notice Gas limit for the destination ccipReceive execution.
    function gasLimit() external view returns (uint256);

    /// @notice Receive a CCIP message (tokens and/or a report).
    function ccipReceive(Client.Any2EVMMessage calldata _message) external;

    /// @notice ERC165 support check used by the router.
    function supportsInterface(
        bytes4 _interfaceId
    ) external view returns (bool);

    /// @notice Rescue ETH held for CCIP fees.
    function rescueETH(address _to, uint256 _amount) external;
}

/// @title ICCIPStrategy
/// @notice Interface for the origin CCIPStrategy.
interface ICCIPStrategy is IBaseCrossChain, IBaseCCIP {
    /// @notice Rescue tokens accidentally sent to this contract.
    function rescue(address _token, address _to, uint256 _amount) external;
}

/// @title ICCIPRemoteStrategy
/// @notice Interface for the remote CCIPRemoteStrategy.
interface ICCIPRemoteStrategy is IBaseRemoteStrategy, IBaseCCIP {
    /// @notice The ERC4626 vault assets are deployed into.
    function vault() external view returns (address);

    /// @notice Rescue tokens accidentally sent to this contract.
    function rescue(address _token, address _to, uint256 _amount) external;
}

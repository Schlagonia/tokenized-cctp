// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title Client
/// @notice Chainlink CCIP message types + extraArgs helper. Vendored from
///         Chainlink's contracts-ccip package to avoid the full dependency.
library Client {
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender; // abi-encoded source-chain sender address
        bytes data;
        EVMTokenAmount[] destTokenAmounts;
    }

    struct EVM2AnyMessage {
        bytes receiver; // abi-encoded destination address
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken; // address(0) == native gas token
        bytes extraArgs;
    }

    bytes4 internal constant GENERIC_EXTRA_ARGS_V2_TAG = 0x181dcf10;

    struct EVMExtraArgsV2 {
        uint256 gasLimit;
        bool allowOutOfOrderExecution;
    }

    function _argsToBytes(
        EVMExtraArgsV2 memory _extraArgs
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(GENERIC_EXTRA_ARGS_V2_TAG, _extraArgs);
    }
}

/// @title IRouterClient
/// @notice Minimal interface for the CCIP Router used to send messages.
interface IRouterClient {
    function isChainSupported(
        uint64 _destChainSelector
    ) external view returns (bool);

    function getFee(
        uint64 _destinationChainSelector,
        Client.EVM2AnyMessage memory _message
    ) external view returns (uint256 fee);

    function ccipSend(
        uint64 _destinationChainSelector,
        Client.EVM2AnyMessage calldata _message
    ) external payable returns (bytes32);
}

/// @title IAny2EVMMessageReceiver
/// @notice The receive side of a CCIP message. The router calls ccipReceive
///         after verifying the message (and checks supportsInterface first).
interface IAny2EVMMessageReceiver {
    function ccipReceive(Client.Any2EVMMessage calldata _message) external;
}

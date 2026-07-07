// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Client, IRouterClient, IAny2EVMMessageReceiver} from "../interfaces/ccip/ICCIP.sol";

/// @notice Chainlink CCIP bridge base for cross-chain strategies.
/// @dev Mirrors BaseOFT/BaseCCTP: tokens are bridged and report messages are
///      sent over the SAME CCIP router — CCIP carries tokens and data in one
///      message, so a report is just the `data` field (sent data-only, or with
///      a token transfer). The counterpart receives it in `ccipReceive`.
///      Native LayerZero-style fees are paid in the native gas token from this
///      contract's ETH balance.
abstract contract BaseCCIP is IAny2EVMMessageReceiver, IERC165 {
    using SafeERC20 for ERC20;

    event CCIPSent(bytes32 messageId, uint256 amount, bool report, uint256 fee);

    /// @notice The CCIP router on this chain.
    IRouterClient public immutable ROUTER;

    /// @notice CCIP chain selector of the counterpart chain.
    uint64 public immutable REMOTE_CHAIN_SELECTOR;

    /// @notice Gas limit for the destination ccipReceive execution.
    uint256 public gasLimit;

    constructor(
        address _router,
        uint64 _remoteChainSelector,
        uint256 _gasLimit
    ) {
        require(_router != address(0), "ZeroAddress");
        ROUTER = IRouterClient(_router);
        REMOTE_CHAIN_SELECTOR = _remoteChainSelector;
        gasLimit = _gasLimit;
    }

    /*//////////////////////////////////////////////////////////////
                        SEND (TOKENS + REPORT)
    //////////////////////////////////////////////////////////////*/

    /// @notice Send `_amount` of the asset to the counterpart strategy,
    ///         optionally carrying a report as the message data.
    /// @param _amount Amount to bridge (may be 0 for a data-only report)
    /// @param _report Optional report payload; empty for a token-only transfer
    /// @return The amount bridged
    function _ccipSend(
        uint256 _amount,
        bytes memory _report
    ) internal returns (uint256) {
        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount > 0) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _ccipToken(),
                amount: _amount
            });
            ERC20(_ccipToken()).forceApprove(address(ROUTER), _amount);
        }

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_peer()),
            data: _report,
            tokenAmounts: tokenAmounts,
            feeToken: address(0), // native
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: gasLimit,
                    allowOutOfOrderExecution: true
                })
            )
        });

        uint256 fee = ROUTER.getFee(REMOTE_CHAIN_SELECTOR, message);
        require(address(this).balance >= fee, "!fee");

        bytes32 messageId = ROUTER.ccipSend{value: fee}(
            REMOTE_CHAIN_SELECTOR,
            message
        );

        emit CCIPSent(messageId, _amount, _report.length > 0, fee);
        return _amount;
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive a CCIP message (tokens and/or a report) from the
    ///         counterpart, delivered by the router.
    function ccipReceive(
        Client.Any2EVMMessage calldata _message
    ) external virtual override {
        require(msg.sender == address(ROUTER), "!router");
        require(
            _message.sourceChainSelector == REMOTE_CHAIN_SELECTOR,
            "!srcChain"
        );
        require(abi.decode(_message.sender, (address)) == _peer(), "!sender");

        // Any tokens in the message have already been credited to this
        // contract by the router; only a report needs handling.
        if (_message.data.length > 0) {
            _handleCcipMessage(_message.data);
        }
    }

    /// @notice ERC165 — the router checks this before delivering.
    function supportsInterface(
        bytes4 _interfaceId
    ) public pure virtual override returns (bool) {
        return
            _interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _rescueETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "!eth");
    }

    /// @notice The token to bridge (the strategy asset).
    function _ccipToken() internal view virtual returns (address);

    /// @notice The counterpart strategy on REMOTE_CHAIN_SELECTOR.
    function _peer() internal view virtual returns (address);

    /// @notice Handle a report payload. Overridden by the receiver (origin);
    ///         reverts on the send-only side (remote).
    function _handleCcipMessage(bytes memory _data) internal virtual;

    /// @notice Accept ETH for CCIP native fees.
    receive() external payable virtual {}
}

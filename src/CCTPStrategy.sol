// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseCrossChain} from "./bases/BaseCrossChain.sol";
import {BaseCCTP} from "./BaseCCTP.sol";

/// @notice Strategy that bridges native USDC via CCTP to a destination chain
/// and tracks the remote deployed capital through periodic accounting updates.
contract CCTPStrategy is BaseCrossChain, BaseCCTP {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        string memory _name,
        address _tokenMessenger,
        address _messageTransmitter,
        uint32 _remoteDomain,
        address _remoteCounterpart,
        address _depositer
    )
        BaseCrossChain(
            _asset,
            _name,
            bytes32(uint256(_remoteDomain)),
            _remoteCounterpart,
            _depositer
        )
        BaseCCTP(_tokenMessenger, _messageTransmitter)
    {
        asset.forceApprove(_tokenMessenger, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                    BASECROSSCHAIN IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets to remote chain via CCTP
    /// @dev Called by BaseCrossChain._deployFunds()
    function _bridgeAssets(
        uint256 _amount,
        bytes memory _data
    ) internal override returns (uint256) {
        TOKEN_MESSENGER.depositForBurnWithHook(
            _amount,
            uint32(uint256(REMOTE_ID)),
            _addressToBytes32(REMOTE_COUNTERPART),
            address(asset),
            bytes32(0),
            0,
            FINALITY_THRESHOLD_FINALIZED,
            _data
        );

        return _amount;
    }

    /*//////////////////////////////////////////////////////////////
                        CCTP MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle incoming CCTP message
    /// @dev Validates CCTP-specific requirements and routes to _receiveMessage
    function handleReceiveFinalizedMessage(
        uint32 _sourceDomain,
        bytes32 _sender,
        uint32 _finalityThresholdExecuted,
        bytes calldata _messageBody
    ) external virtual override returns (bool) {
        require(
            msg.sender == address(MESSAGE_TRANSMITTER),
            "InvalidTransmitter"
        );
        require(_sourceDomain == uint32(uint256(REMOTE_ID)), "InvalidDomain");
        require(
            _sender == _addressToBytes32(REMOTE_COUNTERPART),
            "InvalidSender"
        );
        require(_messageBody.length > 0, "EmptyMessage");
        require(
            _finalityThresholdExecuted >= FINALITY_THRESHOLD_FINALIZED,
            "InvalidFinalityThreshold"
        );

        (uint256 requestId, int256 amount) = abi.decode(
            _messageBody,
            (uint256, int256)
        );

        _handleIncomingMessage(requestId, amount);

        return true;
    }
}

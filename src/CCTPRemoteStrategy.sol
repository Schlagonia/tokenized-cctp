// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseRemoteStrategy} from "./bases/BaseRemoteStrategy.sol";
import {BaseCCTP} from "./bases/BaseCCTP.sol";

/// @notice Remote strategy that receives USDC via CCTP and deploys to ERC4626 vault
/// @dev Handles deposits, withdrawals, and profit/loss reporting via CCTP
contract CCTPRemoteStrategy is BaseRemoteStrategy, BaseCCTP {
    using SafeERC20 for *;

    constructor(
        address _asset,
        address _vault,
        address _governance,
        address _tokenMessenger,
        address _messageTransmitter,
        uint32 _sourceDomain,
        address _remoteCounterpart
    )
        BaseRemoteStrategy(
            _asset,
            _vault,
            _governance,
            bytes32(uint256(_sourceDomain)),
            _remoteCounterpart
        )
        BaseCCTP(_asset, _tokenMessenger, _messageTransmitter)
    {
        asset.forceApprove(_tokenMessenger, type(uint256).max);
        asset.forceApprove(_vault, type(uint256).max);
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

    /*//////////////////////////////////////////////////////////////
                BASEREMOTESTRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets back to origin chain via CCTP
    /// @dev Uses depositForBurnWithHook with encoded data
    function _bridgeAssets(
        uint256 amount,
        bytes memory data
    ) internal override returns (uint256) {
        TOKEN_MESSENGER.depositForBurnWithHook(
            amount,
            uint32(uint256(REMOTE_ID)),
            _addressToBytes32(REMOTE_COUNTERPART),
            address(asset),
            bytes32(0),
            0,
            FINALITY_THRESHOLD_FINALIZED,
            data
        );

        return amount;
    }

    /// @notice Send profit/loss message to origin chain via CCTP
    /// @dev Uses sendMessage without token transfer
    function _bridgeMessage(bytes memory data) internal override {
        MESSAGE_TRANSMITTER.sendMessage(
            uint32(uint256(REMOTE_ID)),
            _addressToBytes32(REMOTE_COUNTERPART),
            bytes32(0),
            FINALITY_THRESHOLD_FINALIZED,
            data
        );
    }
}

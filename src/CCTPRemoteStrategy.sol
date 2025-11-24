// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseRemote4626} from "./bases/BaseRemote4626.sol";
import {BaseCCTP} from "./bases/BaseCCTP.sol";

/// @notice Remote strategy that receives USDC via CCTP and deploys to ERC4626 vault
/// @dev Handles deposits, withdrawals, and profit/loss reporting via CCTP
contract CCTPRemoteStrategy is BaseRemote4626, BaseCCTP {
    using SafeERC20 for *;

    constructor(
        address _asset,
        address _governance,
        address _tokenMessenger,
        address _messageTransmitter,
        uint32 _sourceDomain,
        address _remoteCounterpart,
        address _vault
    )
        BaseRemote4626(
            _asset,
            _governance,
            bytes32(uint256(_sourceDomain)),
            _remoteCounterpart,
            _vault
        )
        BaseCCTP(_asset, _tokenMessenger, _messageTransmitter)
    {
        // Approve token messenger for CCTP bridging
        asset.forceApprove(_tokenMessenger, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                BASEREMOTESTRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets back to origin chain via CCTP
    function _bridgeAssets(uint256 amount) internal override returns (uint256) {
        TOKEN_MESSENGER.depositForBurn(
            amount,
            uint32(uint256(REMOTE_ID)),
            _addressToBytes32(REMOTE_COUNTERPART),
            address(asset),
            bytes32(0),
            0,
            FINALITY_THRESHOLD_FINALIZED
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

    /// @notice Handle incoming CCTP message (required by IMessageHandlerV2)
    /// @dev Remote strategies typically don't receive messages, but interface requires implementation
    function handleReceiveFinalizedMessage(
        uint32, // _sourceDomain
        bytes32, // _sender
        uint32, // _finalityThresholdExecuted
        bytes calldata // _messageBody
    ) external virtual override returns (bool) {
        // Remote strategies don't process incoming messages
        // Only origin strategy receives messages from remote
        return false;
    }

    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyGovernance {
        require(
            _token != address(asset) && _token != address(vault),
            "Invalid token"
        );
        ERC20(_token).safeTransfer(_to, _amount);
    }
}

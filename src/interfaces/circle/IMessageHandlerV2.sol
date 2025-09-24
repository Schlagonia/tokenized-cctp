// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/**
 * @title IMessageHandlerV2
 * @notice Handles messages on the destination domain, forwarded from
 * an IReceiverV2.
 */
interface IMessageHandlerV2 {
    /**
     * @notice Handles an incoming finalized message from an IReceiverV2
     * @dev Finalized messages have finality threshold values greater than or equal to 2000
     * @param sourceDomain The source domain of the message
     * @param sender The sender of the message
     * @param finalityThresholdExecuted the finality threshold at which the message was attested to
     * @param messageBody The raw bytes of the message body
     * @return success True, if successful; false, if not.
     */
    function handleReceiveFinalizedMessage(
        uint32 sourceDomain,
        bytes32 sender,
        uint32 finalityThresholdExecuted,
        bytes calldata messageBody
    ) external returns (bool);
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOFT, ILayerZeroComposer, SendParam, MessagingFee, OFTReceipt} from "./IOFT.sol";
import {OFTComposeMsgCodec} from "./OFTComposeMsgCodec.sol";

/// @notice LayerZero bridge base for cross-chain strategies.
/// @dev Tokens AND report messages both travel over the SAME OFT bridge, so
///      the strategy reuses the OFT's existing LayerZero configuration and
///      needs none of its own — no delegate, no library/DVN wiring. A report
///      is attached to an OFT `send` as a compose message: alongside a real
///      token transfer, or as a 0-amount send purely to carry a standalone
///      report. The origin receives it in `lzCompose`. `lzOptions` (the
///      executor gas for delivery/compose) is set once at construction by the
///      factory. Native fees are paid from this contract's ETH balance.
abstract contract BaseOFT is ILayerZeroComposer {
    using SafeERC20 for ERC20;
    using OFTComposeMsgCodec for bytes;

    event OFTSent(uint256 amountReceived, bool report, uint256 nativeFee);

    /// @notice The OFT (or OFT adapter) that bridges the strategy asset.
    IOFT public immutable OFT;

    /// @notice The LayerZero V2 endpoint on this chain (only used to
    ///         authenticate lzCompose callers).
    address public immutable ENDPOINT;

    /// @notice LayerZero endpoint ID of the counterpart chain.
    uint32 public immutable REMOTE_EID;

    /// @notice Type-3 executor options attached to sends (lzReceive + lzCompose
    ///         gas). Computed and set by the factory at construction.
    bytes public lzOptions;

    constructor(
        address _oft,
        address _endpoint,
        uint32 _remoteEid,
        bytes memory _lzOptions
    ) {
        require(_oft != address(0) && _endpoint != address(0), "ZeroAddress");

        OFT = IOFT(_oft);
        ENDPOINT = _endpoint;
        REMOTE_EID = _remoteEid;
        lzOptions = _lzOptions;
    }

    /*//////////////////////////////////////////////////////////////
                        SEND (TOKENS + REPORT)
    //////////////////////////////////////////////////////////////*/

    /// @notice Send `_amount` of the OFT token to the counterpart strategy,
    ///         optionally carrying a report as a compose message.
    /// @dev `_amount` may be 0 to send a report with no token movement.
    ///      Credits the receipt's amountReceivedLD so shared-decimal
    ///      truncation cannot inflate accounting.
    /// @param _amount Amount to bridge in local decimals (may be 0)
    /// @param _report Optional report payload; empty for a token-only transfer
    /// @return amountReceived The amount credited on the destination chain
    function _oftSend(
        uint256 _amount,
        bytes memory _report
    ) internal returns (uint256 amountReceived) {
        uint256 minAmountLD = _amount == 0
            ? 0
            : _amount - (_amount % OFT.decimalConversionRate());

        SendParam memory sendParam = SendParam({
            dstEid: REMOTE_EID,
            to: _peer(),
            amountLD: _amount,
            minAmountLD: minAmountLD,
            extraOptions: lzOptions,
            composeMsg: _report,
            oftCmd: ""
        });

        if (_amount > 0 && OFT.approvalRequired()) {
            ERC20(OFT.token()).forceApprove(address(OFT), _amount);
        }

        MessagingFee memory fee = OFT.quoteSend(sendParam, false);
        require(address(this).balance >= fee.nativeFee, "!fee");

        (, OFTReceipt memory receipt) = OFT.send{value: fee.nativeFee}(
            sendParam,
            fee,
            address(this)
        );

        amountReceived = receipt.amountReceivedLD;
        emit OFTSent(amountReceived, _report.length > 0, fee.nativeFee);
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE (COMPOSE)
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive a report attached to an OFT transfer from the
    ///         counterpart, delivered by the endpoint after the OFT credits
    ///         this contract.
    function lzCompose(
        address _from,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) external payable virtual override {
        require(msg.sender == ENDPOINT, "!endpoint");
        require(_from == address(OFT), "!oft");
        require(_message.srcEid() == REMOTE_EID, "!srcEid");
        require(_message.composeFrom() == _peer(), "!sender");

        _handleComposeMessage(_message.composeMsg());
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _rescueETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "!eth");
    }

    function _addressToBytes32(
        address _address
    ) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }

    /// @notice The counterpart strategy on REMOTE_EID, as a bytes32.
    function _peer() internal view virtual returns (bytes32);

    /// @notice Handle a decoded report payload. Overridden by the receiver
    ///         (origin); reverts on the send-only side (remote).
    function _handleComposeMessage(bytes memory _payload) internal virtual;

    /// @notice Accept ETH for LayerZero native fees and send() refunds.
    receive() external payable virtual {}
}

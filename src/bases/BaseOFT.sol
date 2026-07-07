// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOFT, SendParam, OFTReceipt} from "../interfaces/layerzero/IOFT.sol";
import {ILayerZeroReceiver} from "../interfaces/layerzero/ILayerZeroReceiver.sol";
import {ILayerZeroEndpointV2, Origin, MessagingParams, MessagingFee, MessagingReceipt} from "../interfaces/layerzero/ILayerZeroEndpointV2.sol";

/// @notice LayerZero bridge base for cross-chain strategies.
/// @dev Bundles two LayerZero channels, mirroring how BaseCCTP bundles the
///      CCTP token bridge with CCTP messaging:
///        1. Token transfers via an OFT / OFT adapter (`_oftSend`).
///        2. Report messages via the endpoint as a lightweight OApp
///           (`_lzSend` / `lzReceive`).
///      Native LayerZero fees are paid from this contract's ETH balance
///      (pre-fund via receive() or attach msg.value to the triggering call).
///      The message peer is the counterpart strategy; concrete contracts
///      supply it via `_peer()` (the immutable REMOTE_COUNTERPART).
abstract contract BaseOFT is ILayerZeroReceiver {
    using SafeERC20 for ERC20;

    event OFTSent(uint256 amountReceived, uint256 nativeFee);

    event ReportSent(uint256 nativeFee);

    event LzOptionsSet(bytes options);

    /// @notice The OFT (or OFT adapter) that bridges the strategy asset.
    IOFT public immutable OFT;

    /// @notice The LayerZero V2 endpoint on this chain.
    ILayerZeroEndpointV2 public immutable ENDPOINT;

    /// @notice LayerZero endpoint ID of the counterpart chain.
    uint32 public immutable REMOTE_EID;

    /// @notice Executor options for report messages (type-3). Empty relies on
    ///         the OApp's enforced options configured via the delegate.
    bytes public lzOptions;

    constructor(
        address _oft,
        address _endpoint,
        uint32 _remoteEid,
        address _delegate
    ) {
        require(
            _oft != address(0) &&
                _endpoint != address(0) &&
                _delegate != address(0),
            "ZeroAddress"
        );

        OFT = IOFT(_oft);
        ENDPOINT = ILayerZeroEndpointV2(_endpoint);
        REMOTE_EID = _remoteEid;

        // The delegate configures the OApp's send/receive libraries and DVNs.
        ENDPOINT.setDelegate(_delegate);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN BRIDGING (OFT)
    //////////////////////////////////////////////////////////////*/

    /// @notice Send `_amount` of the OFT token to the counterpart strategy.
    /// @dev Credits the receipt's amountReceivedLD so shared-decimal
    ///      truncation cannot inflate accounting.
    /// @param _amount Amount to bridge in local decimals
    /// @return amountReceived The amount credited on the destination chain
    function _oftSend(
        uint256 _amount
    ) internal returns (uint256 amountReceived) {
        // Remove shared-decimal dust the same way the OFT will.
        uint256 minAmountLD = _amount - (_amount % OFT.decimalConversionRate());

        SendParam memory sendParam = SendParam({
            dstEid: REMOTE_EID,
            to: _peer(),
            amountLD: _amount,
            minAmountLD: minAmountLD,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        if (OFT.approvalRequired()) {
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
        emit OFTSent(amountReceived, fee.nativeFee);
    }

    /*//////////////////////////////////////////////////////////////
                        REPORT MESSAGING (OApp)
    //////////////////////////////////////////////////////////////*/

    /// @notice Send a report message to the counterpart strategy.
    /// @param _message Encoded report payload
    function _lzSend(bytes memory _message) internal {
        MessagingParams memory params = MessagingParams({
            dstEid: REMOTE_EID,
            receiver: _peer(),
            message: _message,
            options: lzOptions,
            payInLzToken: false
        });

        MessagingFee memory fee = ENDPOINT.quote(params, address(this));
        require(address(this).balance >= fee.nativeFee, "!fee");

        ENDPOINT.send{value: fee.nativeFee}(params, address(this));
        emit ReportSent(fee.nativeFee);
    }

    /// @notice Receive a verified LayerZero message from the endpoint.
    function lzReceive(
        Origin calldata _origin,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) external payable virtual override {
        require(msg.sender == address(ENDPOINT), "!endpoint");
        require(_origin.srcEid == REMOTE_EID, "!srcEid");
        require(_origin.sender == _peer(), "!sender");

        _handleLzMessage(_message);
    }

    /// @notice Whether a pathway from `_origin` may be initialized.
    function allowInitializePath(
        Origin calldata _origin
    ) external view virtual override returns (bool) {
        return _origin.srcEid == REMOTE_EID && _origin.sender == _peer();
    }

    /// @notice Unordered delivery — no nonce enforcement.
    function nextNonce(
        uint32 /* _srcEid */,
        bytes32 /* _sender */
    ) external view virtual override returns (uint64) {
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _setLzOptions(bytes memory _options) internal {
        lzOptions = _options;
        emit LzOptionsSet(_options);
    }

    function _rescueETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "!eth");
    }

    function _addressToBytes32(
        address _address
    ) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }

    /// @notice The counterpart strategy on REMOTE_EID, as an OApp peer.
    function _peer() internal view virtual returns (bytes32);

    /// @notice Handle a decoded report message. Overridden by the receiver
    ///         (origin); reverts on the send-only side (remote).
    function _handleLzMessage(bytes calldata _message) internal virtual;

    /// @notice Accept ETH for LayerZero native fees and send() refunds.
    receive() external payable virtual {}
}

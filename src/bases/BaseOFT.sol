// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOFT, SendParam, OFTReceipt} from "../interfaces/layerzero/IOFT.sol";
import {ILayerZeroComposer} from "../interfaces/layerzero/ILayerZeroComposer.sol";
import {ILayerZeroEndpointV2, MessagingFee, MessagingReceipt} from "../interfaces/layerzero/ILayerZeroEndpointV2.sol";

/// @notice LayerZero bridge base for cross-chain strategies.
/// @dev Tokens AND report messages both travel over the SAME OFT bridge, so
///      the strategy reuses the OFT's existing LayerZero configuration (DVNs,
///      libraries, enforced options) and needs none of its own. A report is
///      attached to an OFT `send` as a compose message: alongside a real token
///      transfer, or as a 0-amount send purely to carry a standalone report.
///      The origin receives it in `lzCompose`. Native fees are paid from this
///      contract's ETH balance (pre-fund via receive() or attach msg.value).
abstract contract BaseOFT is ILayerZeroComposer {
    using SafeERC20 for ERC20;

    event OFTSent(uint256 amountReceived, bool report, uint256 nativeFee);

    event LzOptionsSet(bytes options);

    /// @notice Offsets into the OFT compose message (OFTComposeMsgCodec):
    ///         [0:8] nonce, [8:12] srcEid, [12:44] amountLD,
    ///         [44:76] composeFrom, [76:] the attached payload.
    uint256 internal constant SRC_EID_OFFSET = 8;
    uint256 internal constant AMOUNT_LD_OFFSET = 12;
    uint256 internal constant COMPOSE_FROM_OFFSET = 44;
    uint256 internal constant COMPOSE_MSG_OFFSET = 76;

    /// @notice The OFT (or OFT adapter) that bridges the strategy asset.
    IOFT public immutable OFT;

    /// @notice The LayerZero V2 endpoint on this chain.
    ILayerZeroEndpointV2 public immutable ENDPOINT;

    /// @notice LayerZero endpoint ID of the counterpart chain.
    uint32 public immutable REMOTE_EID;

    /// @notice Executor options (type-3) attached to sends. When a report is
    ///         attached these must include a compose option so the report
    ///         executes on arrival. Built off-chain with LayerZero's
    ///         OptionsBuilder and set by the strategy's admin.
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

        // Delegate can adjust the OApp config if ever needed; not required for
        // the compose path since the OFT is already configured.
        ENDPOINT.setDelegate(_delegate);
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
        require(msg.sender == address(ENDPOINT), "!endpoint");
        require(_from == address(OFT), "!oft");

        uint32 srcEid = uint32(
            bytes4(_message[SRC_EID_OFFSET:AMOUNT_LD_OFFSET])
        );
        require(srcEid == REMOTE_EID, "!srcEid");

        bytes32 composeFrom = bytes32(
            _message[COMPOSE_FROM_OFFSET:COMPOSE_MSG_OFFSET]
        );
        require(composeFrom == _peer(), "!sender");

        _handleComposeMessage(_message[COMPOSE_MSG_OFFSET:]);
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

    /// @notice The counterpart strategy on REMOTE_EID, as a bytes32.
    function _peer() internal view virtual returns (bytes32);

    /// @notice Handle a decoded report payload. Overridden by the receiver
    ///         (origin); reverts on the send-only side (remote).
    function _handleComposeMessage(bytes calldata _payload) internal virtual;

    /// @notice Accept ETH for LayerZero native fees and send() refunds.
    receive() external payable virtual {}
}

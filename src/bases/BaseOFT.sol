// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOFT, SendParam, MessagingFee, OFTReceipt, MessagingReceipt} from "../interfaces/layerzero/IOFT.sol";

/// @notice LayerZero V2 OFT base contract for cross-chain token transfers
/// @dev Native fees are paid from this contract's ETH balance. The contract
///      can be pre-funded via receive() or funded per-call through payable
///      bridge functions on the inheriting contract.
abstract contract BaseOFT {
    using SafeERC20 for ERC20;

    event OFTSent(
        address indexed oft,
        uint32 indexed dstEid,
        uint256 amountSent,
        uint256 nativeFee
    );

    /// @notice Send tokens through a LayerZero V2 OFT.
    /// @dev The minimum receive amount is pinned to the send amount minus
    ///      shared-decimal dust, so nothing beyond truncation can be skimmed.
    ///      Returns the receipt's amountReceivedLD (what actually arrives on
    ///      the destination) so truncation can never inflate accounting.
    /// @param _oft The OFT (or OFT adapter) contract to send through
    /// @param _dstEid Destination LayerZero endpoint ID
    /// @param _to Recipient on the destination chain
    /// @param _amountLD Amount to send in local decimals
    /// @return amountReceivedLD The amount credited on the destination chain
    function _oftSend(
        address _oft,
        uint32 _dstEid,
        address _to,
        uint256 _amountLD
    ) internal returns (uint256 amountReceivedLD) {
        // Remove shared-decimal dust the same way the OFT will.
        uint256 minAmountLD = _amountLD -
            (_amountLD % IOFT(_oft).decimalConversionRate());

        SendParam memory sendParam = SendParam({
            dstEid: _dstEid,
            to: bytes32(uint256(uint160(_to))),
            amountLD: _amountLD,
            minAmountLD: minAmountLD,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        // Adapter (lockbox) OFTs pull the underlying token via transferFrom.
        if (IOFT(_oft).approvalRequired()) {
            ERC20(IOFT(_oft).token()).forceApprove(_oft, _amountLD);
        }

        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        require(address(this).balance >= fee.nativeFee, "!fee");

        (, OFTReceipt memory receipt) = IOFT(_oft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            address(this)
        );

        amountReceivedLD = receipt.amountReceivedLD;

        emit OFTSent(_oft, _dstEid, amountReceivedLD, fee.nativeFee);
    }

    /// @dev Send ETH held for LayerZero fees to a recipient.
    function _rescueETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "!eth");
    }

    /// @notice Accept ETH for LayerZero native fees and send() refunds.
    receive() external payable virtual {}
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseCrossChain} from "./bases/BaseCrossChain.sol";
import {BaseOFT} from "./bases/BaseOFT.sol";

/// @title OFTStrategy
/// @notice Origin strategy that bridges its asset to a remote chain via a
///         LayerZero OFT and tracks the remote deployment through OApp report
///         messages (e.g. USDG to Robinhood).
/// @dev Assets are bridged on deposit via the OFT; the remote reports its
///      totalAssets back over LayerZero, delivered to `lzReceive`. The
///      strategy must hold an ETH reserve to pay LayerZero native fees.
contract OFTStrategy is BaseCrossChain, BaseOFT {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        string memory _name,
        address _oft,
        address _endpoint,
        uint32 _remoteEid,
        uint256 _remoteChainId,
        address _remoteCounterpart,
        address _depositer,
        address _delegate
    )
        BaseCrossChain(
            _asset,
            _name,
            bytes32(uint256(_remoteEid)),
            _remoteChainId,
            _remoteCounterpart,
            _depositer
        )
        BaseOFT(_oft, _endpoint, _remoteEid, _delegate)
    {
        require(OFT.token() == _asset, "OftMismatch");
    }

    /*//////////////////////////////////////////////////////////////
                    BASECROSSCHAIN IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets to the remote chain via the OFT.
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        return _oftSend(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                        LAYERZERO OApp
    //////////////////////////////////////////////////////////////*/

    /// @notice Decode and apply a remote report (totalAssets, timestamp).
    function _handleLzMessage(bytes calldata _message) internal override {
        require(_message.length > 0, "EmptyMessage");
        (uint256 amount, uint256 timestamp) = abi.decode(
            _message,
            (uint256, uint256)
        );
        _handleIncomingMessage(amount, timestamp);
    }

    function _peer() internal view override returns (bytes32) {
        return _addressToBytes32(REMOTE_COUNTERPART);
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the LayerZero endpoint delegate (DVN/library config).
    function setDelegate(address _delegate) external onlyManagement {
        ENDPOINT.setDelegate(_delegate);
    }

    /// @notice Set executor options for report messages.
    function setLzOptions(bytes calldata _options) external onlyManagement {
        _setLzOptions(_options);
    }

    /// @notice Rescue ETH held for LayerZero fees.
    function rescueETH(address _to, uint256 _amount) external onlyManagement {
        _rescueETH(_to, _amount);
    }

    /// @notice Rescue tokens accidentally sent to this contract.
    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyManagement {
        require(_token != address(asset), "InvalidToken");
        ERC20(_token).safeTransfer(_to, _amount);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseCrossChain} from "../bases/BaseCrossChain.sol";
import {BaseCCIP} from "../bases/BaseCCIP.sol";

/// @title CCIPStrategy
/// @notice Origin strategy that bridges its asset to a remote chain via
///         Chainlink CCIP and tracks the remote deployment through report
///         messages carried over the same CCIP router.
/// @dev Assets are bridged on deposit; the remote reports its totalAssets back
///      over CCIP, delivered here in `ccipReceive`. The strategy must hold an
///      ETH reserve to pay CCIP native fees.
contract CCIPStrategy is BaseCrossChain, BaseCCIP {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        string memory _name,
        address _router,
        uint64 _remoteChainSelector,
        uint256 _remoteChainId,
        address _remoteCounterpart,
        uint256 _gasLimit
    )
        BaseCrossChain(
            _asset,
            _name,
            bytes32(uint256(_remoteChainSelector)),
            _remoteChainId,
            _remoteCounterpart
        )
        BaseCCIP(_router, _remoteChainSelector, _gasLimit)
    {}

    /*//////////////////////////////////////////////////////////////
                    BASECROSSCHAIN IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets to the remote chain via CCIP (no report).
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        return _ccipSend(_amount, "");
    }

    /*//////////////////////////////////////////////////////////////
                            CCIP HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @notice Decode and apply a remote report (totalAssets, timestamp).
    function _handleCcipMessage(bytes memory _data) internal override {
        require(_data.length > 0, "EmptyMessage");
        (uint256 amount, uint256 timestamp) = abi.decode(
            _data,
            (uint256, uint256)
        );
        _handleIncomingMessage(amount, timestamp);
    }

    function _ccipToken() internal view override returns (address) {
        return address(asset);
    }

    function _peer() internal view override returns (address) {
        return REMOTE_COUNTERPART;
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the destination ccipReceive gas limit.
    function setGasLimit(uint256 _gasLimit) external onlyManagement {
        _setGasLimit(_gasLimit);
    }

    /// @notice Rescue ETH held for CCIP fees.
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

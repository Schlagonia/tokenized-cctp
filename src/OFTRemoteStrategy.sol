// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseRemote4626} from "./bases/BaseRemote4626.sol";
import {BaseOFT} from "./bases/BaseOFT.sol";

/// @title OFTRemoteStrategy
/// @notice Remote strategy that receives its asset via a LayerZero OFT,
///         deploys it into an ERC4626 vault, and reports totalAssets home over
///         the SAME OFT bridge (e.g. USDG on Robinhood).
/// @dev Bridges assets home via the OFT; reports ride the OFT as compose
///      messages — attached to a real transfer, or as a 0-amount send for a
///      standalone report. Must hold an ETH reserve for LayerZero fees.
contract OFTRemoteStrategy is BaseRemote4626, BaseOFT {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        address _governance,
        address _oft,
        address _endpoint,
        uint32 _originEid,
        address _originCounterpart,
        address _vault,
        address _delegate
    )
        BaseRemote4626(
            _asset,
            _governance,
            bytes32(uint256(_originEid)),
            _originCounterpart,
            _vault
        )
        BaseOFT(_oft, _endpoint, _originEid, _delegate)
    {
        require(OFT.token() == _asset, "OftMismatch");
    }

    /*//////////////////////////////////////////////////////////////
                BASEREMOTESTRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets back to the origin chain via the OFT (no report).
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        return _oftSend(_amount, "");
    }

    /// @notice Send a standalone report home as a 0-amount OFT compose.
    function _bridgeMessage(bytes memory data) internal override {
        _oftSend(0, data);
    }

    /*//////////////////////////////////////////////////////////////
                        LAYERZERO COMPOSE
    //////////////////////////////////////////////////////////////*/

    function _peer() internal view override returns (bytes32) {
        return _addressToBytes32(REMOTE_COUNTERPART);
    }

    /// @dev Remote is send-only; it never ingests reports.
    function _handleComposeMessage(bytes calldata) internal pure override {
        revert("NotSupported");
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the LayerZero endpoint delegate (DVN/library config).
    function setDelegate(address _delegate) external onlyGovernance {
        ENDPOINT.setDelegate(_delegate);
    }

    /// @notice Set executor options for report messages.
    function setLzOptions(bytes calldata _options) external onlyGovernance {
        _setLzOptions(_options);
    }

    /// @notice Rescue ETH held for LayerZero fees.
    function rescueETH(address _to, uint256 _amount) external onlyGovernance {
        _rescueETH(_to, _amount);
    }

    /// @notice Rescue tokens accidentally sent to this contract.
    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyGovernance {
        require(!_isProtectedToken(_token), "InvalidToken");
        ERC20(_token).safeTransfer(_to, _amount);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseRemote4626} from "../bases/BaseRemote4626.sol";
import {BaseCCIP} from "../bases/BaseCCIP.sol";

/// @title CCIPRemoteStrategy
/// @notice Remote strategy that receives its asset via Chainlink CCIP, deploys
///         it into an ERC4626 vault, and reports totalAssets home over CCIP.
/// @dev Bridges assets home and sends data-only report messages via the router.
///      Must hold an ETH reserve to pay CCIP native fees.
contract CCIPRemoteStrategy is BaseRemote4626, BaseCCIP {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        address _governance,
        address _router,
        uint64 _originChainSelector,
        address _originCounterpart,
        address _vault,
        uint256 _gasLimit
    )
        BaseRemote4626(
            _asset,
            _governance,
            bytes32(uint256(_originChainSelector)),
            _originCounterpart,
            _vault
        )
        BaseCCIP(_router, _originChainSelector, _gasLimit)
    {}

    /*//////////////////////////////////////////////////////////////
                BASEREMOTESTRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets back to the origin chain via CCIP (no report).
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        return _ccipSend(_amount, "");
    }

    /// @notice Send a data-only report message to the origin chain via CCIP.
    function _bridgeMessage(bytes memory data) internal override {
        _ccipSend(0, data);
    }

    /*//////////////////////////////////////////////////////////////
                            CCIP HOOKS
    //////////////////////////////////////////////////////////////*/

    function _ccipToken() internal view override returns (address) {
        return address(asset);
    }

    function _peer() internal view override returns (address) {
        return REMOTE_COUNTERPART;
    }

    /// @dev Remote is send-only for reports; it never ingests them.
    function _handleCcipMessage(bytes memory) internal pure override {
        revert("NotSupported");
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Rescue ETH held for CCIP fees.
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

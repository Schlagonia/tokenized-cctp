// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseInventoryOrigin} from "./BaseInventoryOrigin.sol";

/// @notice Generic async-redemption add-on for inventory origin strategies.
/// @dev Bridge-agnostic and protocol-agnostic: it can be layered on top of any
///      BaseInventoryOrigin concrete (LxLy, OFT, CCTP, ...) and any LST/queue.
///      It provides the pending-redemption state machine and blocks reports
///      while a redemption is outstanding (value is indeterminate). Concrete
///      layers implement the protocol specifics via `_initiateRedemption` /
///      `_claimRedemption`. Redeemed value is tracked in `pendingRedemptions`
///      (declared on BaseInventoryOrigin and already folded into totalAssets
///      there); the management escape hatch is `zeroPendingRedemptions`.
abstract contract BaseAsyncRedemption is BaseInventoryOrigin {
    event CooldownInitiated(uint256 indexed id, uint256 pendingAssets);

    event CooldownClaimed(uint256 indexed id, uint256 assets);

    /// @notice Queue collateral for redemption into the underlying asset.
    /// @param _amount Amount of collateral to redeem (capped to balance)
    /// @return id Protocol-specific redemption/request identifier
    function initiateCooldown(
        uint256 _amount
    ) external virtual onlyManagement returns (uint256 id) {
        uint256 balance = balanceOfCollateral();
        if (_amount > balance) _amount = balance;
        require(_amount > 0, "ZeroAmount");

        uint256 pendingAssets;
        (id, pendingAssets) = _initiateRedemption(_amount);

        unchecked {
            pendingRedemptions += pendingAssets;
        }

        emit CooldownInitiated(id, pendingAssets);
    }

    /// @notice Claim a completed redemption, settling it into the asset.
    /// @param _id The redemption/request identifier
    /// @return assets Amount of underlying asset received
    function claimCooldown(
        uint256 _id
    ) external payable virtual onlyKeepers returns (uint256 assets) {
        assets = _claimRedemption(_id);

        if (assets >= pendingRedemptions) {
            delete pendingRedemptions;
        } else {
            unchecked {
                pendingRedemptions -= assets;
            }
        }

        emit CooldownClaimed(_id, assets);
    }

    /// @dev Value is indeterminate while a redemption is pending, so block
    ///      reports until the position is claimed (or written off via
    ///      zeroPendingRedemptions).
    function _harvestAndReport() internal virtual override returns (uint256) {
        require(pendingRedemptions == 0, "pending");
        return super._harvestAndReport();
    }

    /// @notice Initiate a protocol redemption of `_amount` collateral.
    /// @param _amount Amount of collateral to redeem
    /// @return id Protocol-specific identifier for the request
    /// @return pendingAssets Asset-denominated value queued for redemption
    function _initiateRedemption(
        uint256 _amount
    ) internal virtual returns (uint256 id, uint256 pendingAssets);

    /// @notice Claim a completed protocol redemption into the asset.
    /// @param _id Protocol-specific identifier for the request
    /// @return assets Amount of underlying asset received
    function _claimRedemption(
        uint256 _id
    ) internal virtual returns (uint256 assets);
}

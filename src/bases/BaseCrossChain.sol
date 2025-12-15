// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";

/// @notice Base contract for cross-chain strategies on the origin chain
/// @dev Provides message ordering, remote asset tracking, and abstract bridging interface
abstract contract BaseCrossChain is BaseHealthCheck {
    /// @notice Address allowed to deposit into this strategy
    address public immutable DEPOSITER;

    /// @notice Remote chain identifier (can be domain ID, chain ID, etc.)
    bytes32 public immutable REMOTE_ID;

    /// @notice Address of the remote strategy counterpart
    address public immutable REMOTE_COUNTERPART;

    /// @notice Tracks remote assets
    uint256 public remoteAssets;

    constructor(
        address _asset,
        string memory _name,
        bytes32 _remoteId,
        address _remoteCounterpart,
        address _depositer
    ) BaseHealthCheck(_asset, _name) {
        require(_remoteCounterpart != address(0), "ZeroAddress");
        require(_depositer != address(0), "ZeroAddress");
        // Note: _remoteId can be 0 for some chains (e.g., Ethereum domain = 0)

        REMOTE_ID = _remoteId;
        REMOTE_COUNTERPART = _remoteCounterpart;
        DEPOSITER = _depositer;

        _setProfitLimitRatio(1_000); // 10%
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reports total assets including remote deployments
    /// @return _totalAssets Sum of local balance and remote assets
    function _harvestAndReport()
        internal
        virtual
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = balanceOfAsset() + remoteAssets;
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAW LIMIT OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Only local balance is available for withdrawal
    /// @dev Remote assets must be bridged back before withdrawal
    function availableWithdrawLimit(
        address /* _owner */
    ) public view virtual override returns (uint256) {
        return balanceOfAsset();
    }

    /// @notice Restrict deposits to specific depositer address
    /// @dev Override to change deposit access control
    function availableDepositLimit(
        address _owner
    ) public view virtual override returns (uint256) {
        return _owner == DEPOSITER ? type(uint256).max : 0;
    }

    /// @notice Handles incoming cross-chain messages
    /// @param amount Signed integer representing asset change (positive = profit, negative = withdrawal)
    function _handleIncomingMessage(uint256 amount) internal virtual {
        // NOTE: Its possible a remote report while funds are in flight would cause an invalid report to cause incorrect losses.
        // We accpet the amount either wauy since _harvestAndReport() will execute health check and make sure the message can
        // not be executed in the future.
        remoteAssets = amount;
    }

    function balanceOfAsset() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy funds to remote chain
    /// @dev Increments request ID, calls bridge implementation, updates remote assets
    function _deployFunds(uint256 _amount) internal virtual override {
        remoteAssets += _bridgeAssets(_amount);
    }

    /// @notice No-op for freeing funds (not needed for cross-chain strategies)
    function _freeFunds(uint256) internal pure virtual override {}

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT METHODS TO IMPLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets to remote chain
    /// @dev Implementation must handle bridge-specific token transfer logic
    /// @param amount Amount of tokens to bridge
    function _bridgeAssets(uint256 amount) internal virtual returns (uint256);
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";

/// @notice Base contract for cross-chain strategies on the origin chain
/// @dev Provides message ordering, remote asset tracking, and abstract bridging interface
abstract contract BaseCrossChain is BaseHealthCheck {
    /// @notice Remote chain identifier (can be domain ID, chain ID, etc.)
    bytes32 public immutable REMOTE_ID;

    /// @notice Address of the remote strategy counterpart
    address public immutable REMOTE_COUNTERPART;

    /// @notice Address allowed to deposit into this strategy
    address public immutable DEPOSITER;

    /// @notice Tracks assets deployed on remote chain
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
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reports total assets including remote deployments
    /// @return _totalAssets Sum of local balance and remote assets
    function _harvestAndReport()
        internal
        view
        virtual
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this)) + remoteAssets;
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAW LIMIT OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Only local balance is available for withdrawal
    /// @dev Remote assets must be bridged back before withdrawal
    function availableWithdrawLimit(
        address /* _owner */
    ) public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
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
    function _handleIncomingMessage(int256 amount) internal virtual {
        // Update remote assets accounting
        // Positive amount = profit reported
        // Negative amount = withdrawal fulfilled or loss reported
        remoteAssets = _toUint256(_toInt256(remoteAssets) + amount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy funds to remote chain
    /// @dev Increments request ID, calls bridge implementation, updates remote assets
    function _deployFunds(uint256 _amount) internal virtual override {
        bytes memory data = abi.encode(_toInt256(_amount));

        uint256 bridged = _bridgeAssets(_amount, data);

        remoteAssets += bridged;
    }

    /// @notice No-op for freeing funds (not needed for cross-chain strategies)
    function _freeFunds(uint256) internal pure virtual override {}

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT METHODS TO IMPLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets to remote chain
    /// @dev Implementation must handle bridge-specific token transfer logic
    /// @param amount Amount of tokens to bridge
    /// @param data Bridge-specific encoded data (includes request ID and amount)
    function _bridgeAssets(
        uint256 amount,
        bytes memory data
    ) internal virtual returns (uint256);

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     *
     * _Available since v3.0._
     */
    function _toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "must be positive");
        return uint256(value);
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     *
     * _Available since v3.0._
     */
    function _toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(
            value <= uint256(type(int256).max),
            "does not fit in an int256"
        );
        return int256(value);
    }
}

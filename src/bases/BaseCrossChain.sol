// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck, ERC20, BaseStrategy} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";

/// @notice Base contract for cross-chain strategies on the origin chain
/// @dev Provides message ordering, remote asset tracking, and abstract bridging interface
abstract contract BaseCrossChain is BaseHealthCheck {
    /// @notice Remote chain identifier (can be domain ID, chain ID, etc.)
    bytes32 public immutable REMOTE_ID;

    /// @notice Address of the remote strategy counterpart
    address public immutable REMOTE_COUNTERPART;

    /// @notice Address allowed to deposit into this strategy
    address public immutable DEPOSITER;

    /// @notice Counter for ordering cross-chain messages
    uint256 public nextRequestId;

    /// @notice Tracks assets deployed on remote chain
    uint256 public remoteAssets;

    /// @notice Mapping to prevent message replay and enforce ordering
    mapping(uint256 => bool) public messageProcessed;

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

        // Start ID's at 1 so ordered checks work
        nextRequestId = 1;
        messageProcessed[0] = true;
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
    /// @dev Validates message ordering and updates remote asset accounting
    /// @param requestId The unique identifier for this message
    /// @param amount Signed integer representing asset change (positive = profit, negative = withdrawal)
    function _handleIncomingMessage(
        uint256 requestId,
        int256 amount
    ) internal virtual {
        require(
            !messageProcessed[requestId],
            "BaseCCTP: Message already processed"
        );
        require(
            messageProcessed[requestId - 1],
            "BaseCCTP: Invalid request ID"
        );

        // Update remote assets accounting
        // Positive amount = profit reported
        // Negative amount = withdrawal fulfilled or loss reported
        remoteAssets = uint256(int256(remoteAssets) + amount);

        // Mark message as processed
        messageProcessed[requestId] = true;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy funds to remote chain
    /// @dev Increments request ID, calls bridge implementation, updates remote assets
    function _deployFunds(uint256 _amount) internal virtual override {
        bytes memory data = abi.encode(nextRequestId, int256(_amount));

        nextRequestId++;

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
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseCrossChain} from "./bases/BaseCrossChain.sol";
import {BaseLxLy} from "./bases/BaseLxLy.sol";
import {IVaultBridgeToken} from "./interfaces/lxly/IVaultBridgeToken.sol";

/// @title KatanaStrategy
/// @notice Strategy that bridges assets via VaultBridgeToken to Katana L2
/// @dev Deposits underlying asset, wraps into vbToken, and bridges to Katana
/// Reports from Katana are received via the LxLy bridge message callback
contract KatanaStrategy is BaseCrossChain, BaseLxLy {
    using SafeERC20 for ERC20;

    /// @notice The VaultBridgeToken contract for wrapping and bridging
    IVaultBridgeToken public immutable VB_TOKEN;

    constructor(
        address _asset,
        string memory _name,
        address _vbToken,
        address _bridge,
        uint32 _remoteNetworkId,
        address _remoteCounterpart,
        address _depositer
    )
        BaseCrossChain(
            _asset,
            _name,
            bytes32(uint256(_remoteNetworkId)),
            _remoteCounterpart,
            _depositer
        )
        BaseLxLy(_bridge)
    {
        require(_vbToken != address(0), "ZeroVbToken");

        VB_TOKEN = IVaultBridgeToken(_vbToken);

        // Verify the vbToken wraps our underlying asset
        require(VB_TOKEN.asset() == _asset, "AssetMismatch");

        // Approve underlying asset to vbToken for depositAndBridge
        asset.forceApprove(_vbToken, type(uint256).max);
    }

    function _harvestAndReport() internal override returns (uint256) {
        _redeemVaultTokens();
        return super._harvestAndReport();
    }

    function redeemVaultTokens() external onlyKeepers {
        _redeemVaultTokens();
    }

    function _redeemVaultTokens() internal {
        uint256 vbBalance = VB_TOKEN.balanceOf(address(this));
        if (vbBalance > 0) {
            VB_TOKEN.redeem(vbBalance, address(this), address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                    BASECROSSCHAIN IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets to Katana via VaultBridgeToken
    /// @dev Deposits underlying into vbToken and bridges to remote chain
    /// @param _amount Amount of underlying asset to bridge
    /// @return The amount bridged
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        // depositAndBridge: deposits underlying -> mints vbToken -> bridges to Katana
        VB_TOKEN.depositAndBridge(
            _amount,
            REMOTE_COUNTERPART,
            uint32(uint256(REMOTE_ID)),
            true // forceUpdateGlobalExitRoot
        );

        return _amount;
    }

    /*//////////////////////////////////////////////////////////////
                        LXLY MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle incoming bridge message from Katana
    /// @dev Called by the bridge when a message is claimed
    /// @param originAddress The sender address on the origin network
    /// @param originNetwork The network ID where the message originated
    /// @param data The message payload (encoded totalAssets)
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable override {
        // Validate the message is from the bridge
        require(msg.sender == address(LXLY_BRIDGE), "InvalidBridge");

        // Validate the message is from our remote counterpart
        require(originNetwork == uint32(uint256(REMOTE_ID)), "InvalidNetwork");
        require(originAddress == REMOTE_COUNTERPART, "InvalidSender");

        // Validate message has data
        require(data.length > 0, "EmptyMessage");

        // Decode the total assets reported by remote strategy
        uint256 amount = abi.decode(data, (uint256));

        // Update remote assets tracking
        _handleIncomingMessage(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Rescue tokens accidentally sent to this contract
    /// @param _token Token to rescue
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyManagement {
        require(_token != address(asset), "InvalidToken");
        ERC20(_token).safeTransfer(_to, _amount);
    }
}

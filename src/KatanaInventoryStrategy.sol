// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseInventoryOrigin} from "./bases/BaseInventoryOrigin.sol";
import {BaseLxLy} from "./bases/BaseLxLy.sol";
import {BaseOFT} from "./bases/BaseOFT.sol";
import {IVaultBridgeToken} from "./interfaces/lxly/IVaultBridgeToken.sol";
import {IOFT} from "./interfaces/layerzero/IOFT.sol";
import {KatanaHelpers} from "./libraries/KatanaHelpers.sol";

/// @title KatanaInventoryStrategy
/// @notice Origin strategy funding looper swap inventory on Katana.
/// @dev The underlying asset bridges to Katana wrapped in a VaultBridgeToken
///      via the LxLy bridge; the collateral token bridges through its
///      LayerZero OFT, or via the LxLy bridge as a wrapped token when no
///      OFT is set. Reports from Katana arrive via the LxLy bridge
///      message callback.
contract KatanaInventoryStrategy is BaseInventoryOrigin, BaseLxLy, BaseOFT {
    using SafeERC20 for ERC20;

    /// @notice The VaultBridgeToken contract for wrapping and bridging asset.
    IVaultBridgeToken public immutable VB_TOKEN;

    /// @notice The LayerZero OFT (adapter) used to bridge the collateral.
    /// @dev address(0) means the collateral bridges via LxLy instead.
    IOFT public immutable COLLATERAL_OFT;

    /// @notice LayerZero endpoint ID of Katana.
    uint32 public constant REMOTE_EID = 30375;

    constructor(
        address _asset,
        string memory _name,
        address _collateral,
        address _oracle,
        address _exchange,
        address _vbToken,
        address _collateralOft,
        address _remoteCounterpart
    )
        BaseInventoryOrigin(
            _asset,
            _name,
            _collateral,
            _oracle,
            _exchange,
            bytes32(uint256(KatanaHelpers.KATANA_NETWORK_ID)),
            747474,
            _remoteCounterpart
        )
        BaseLxLy(KatanaHelpers.UNIFIED_BRIDGE)
    {
        require(_vbToken != address(0), "ZeroVbToken");
        if (_collateralOft != address(0)) {
            require(IOFT(_collateralOft).token() == _collateral, "OftMismatch");
        }

        VB_TOKEN = IVaultBridgeToken(_vbToken);
        COLLATERAL_OFT = IOFT(_collateralOft);

        // Verify the vbToken wraps our underlying asset
        require(VB_TOKEN.asset() == _asset, "AssetMismatch");

        // Approve underlying asset to vbToken for depositAndBridge
        asset.forceApprove(_vbToken, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT TOKEN HANDLING
    //////////////////////////////////////////////////////////////*/

    function _harvestAndReport() internal virtual override returns (uint256) {
        _redeemVaultTokens();
        return super._harvestAndReport() + valueOfVault();
    }

    function valueOfVault() public view virtual returns (uint256) {
        return VB_TOKEN.convertToAssets(VB_TOKEN.balanceOf(address(this)));
    }

    function redeemVaultTokens() external onlyKeepers {
        _redeemVaultTokens();
    }

    function _redeemVaultTokens() internal {
        uint256 maxRedeem = VB_TOKEN.maxRedeem(address(this));
        if (maxRedeem > 0) {
            VB_TOKEN.redeem(maxRedeem, address(this), address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                    BASEINVENTORYORIGIN IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge underlying asset to Katana via VaultBridgeToken
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

    /// @notice Bridge collateral to Katana via its LayerZero OFT, or via
    ///         the LxLy bridge when no OFT is configured.
    /// @param _amount Amount of collateral to bridge
    /// @return The amount received on Katana
    function _bridgeCollateral(
        uint256 _amount
    ) internal virtual override returns (uint256) {
        if (address(COLLATERAL_OFT) != address(0)) {
            return
                _oftSend(
                    address(COLLATERAL_OFT),
                    REMOTE_EID,
                    REMOTE_COUNTERPART,
                    _amount
                );
        }

        collateral.forceApprove(address(LXLY_BRIDGE), _amount);

        LXLY_BRIDGE.bridgeAsset(
            uint32(uint256(REMOTE_ID)),
            REMOTE_COUNTERPART,
            _amount,
            address(collateral),
            true, // forceUpdateGlobalExitRoot
            "" // permitData
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
    /// @param data The message payload (encoded totalAssets and report timestamp)
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
        (uint256 amount, uint256 timestamp) = abi.decode(
            data,
            (uint256, uint256)
        );

        // Update remote assets tracking
        _handleIncomingMessage(amount, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Rescue ETH held for LayerZero fees.
    function rescueETH(address _to, uint256 _amount) external onlyManagement {
        _rescueETH(_to, _amount);
    }

    /// @dev Also protect the vbToken from rescue.
    function _isProtectedToken(
        address _token
    ) internal view virtual override returns (bool) {
        return super._isProtectedToken(_token) || _token == address(VB_TOKEN);
    }
}

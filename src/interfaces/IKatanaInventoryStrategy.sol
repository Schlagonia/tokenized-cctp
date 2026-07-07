// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseInventoryOrigin} from "./IBaseInventoryOrigin.sol";
import {IVaultBridgeToken} from "./lxly/IVaultBridgeToken.sol";
import {IPolygonZkEVMBridgeV2} from "./lxly/IPolygonZkEVMBridgeV2.sol";
import {IOFT} from "./layerzero/IOFT.sol";

/// @title IKatanaInventoryStrategy
/// @notice Interface for the KatanaInventoryStrategy contract
interface IKatanaInventoryStrategy is IBaseInventoryOrigin {
    /*//////////////////////////////////////////////////////////////
                        KATANA-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The VaultBridgeToken contract for wrapping and bridging
    function VB_TOKEN() external view returns (IVaultBridgeToken);

    /// @notice The LayerZero OFT (adapter) used to bridge the collateral
    function COLLATERAL_OFT() external view returns (IOFT);

    /// @notice LayerZero endpoint ID of Katana
    function REMOTE_EID() external view returns (uint32);

    /// @notice Redeem any vbToken held by the strategy for underlying asset
    function redeemVaultTokens() external;

    /// @notice Value of vbToken held by the strategy in underlying assets
    function valueOfVault() external view returns (uint256);

    /// @notice Rescue ETH held for LayerZero fees
    function rescueETH(address _to, uint256 _amount) external;

    /*//////////////////////////////////////////////////////////////
                        LXLY BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The LxLy Unified Bridge contract
    function LXLY_BRIDGE() external view returns (IPolygonZkEVMBridgeV2);

    /// @notice The network ID of the chain this contract is deployed on
    function LOCAL_NETWORK_ID() external view returns (uint32);

    /// @notice Handle incoming bridge message from remote chain
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable;
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseRemoteInventory} from "./bases/BaseRemoteInventory.sol";
import {BaseLxLy} from "./bases/BaseLxLy.sol";
import {BaseOFT} from "./bases/BaseOFT.sol";
import {IOFT} from "./interfaces/layerzero/IOFT.sol";
import {KatanaHelpers} from "./libraries/KatanaHelpers.sol";

/// @title KatanaRemoteInventory
/// @notice Inventory swapper on Katana funded from an origin strategy on
///         Ethereum.
/// @dev Whitelisted loopers swap asset <-> collateral against this contract's
///      balances at oracle price minus a discount. Keepers bridge the
///      underlying asset home via the LxLy bridge (burning the wrapper back
///      to the vbToken) and the collateral home via its LayerZero OFT.
///      Reports go home via LxLy bridge messages.
contract KatanaRemoteInventory is BaseRemoteInventory, BaseLxLy, BaseOFT {
    using SafeERC20 for ERC20;

    /// @notice The LayerZero OFT used to bridge the collateral home.
    /// @dev On Katana the collateral token itself is the OFT. address(0)
    ///      means the collateral bridges home via LxLy instead.
    IOFT public immutable COLLATERAL_OFT;

    /// @notice LayerZero endpoint ID of Ethereum.
    uint32 public constant ORIGIN_EID = 30101;

    constructor(
        address _asset,
        address _collateral,
        address _oracle,
        uint256 _discount,
        address _governance,
        address _collateralOft,
        address _originCounterpart
    )
        BaseRemoteInventory(
            _asset,
            _collateral,
            _oracle,
            _discount,
            _governance,
            bytes32(uint256(KatanaHelpers.ETHEREUM_NETWORK_ID)),
            _originCounterpart
        )
        BaseLxLy(KatanaHelpers.UNIFIED_BRIDGE)
    {
        if (_collateralOft != address(0)) {
            require(IOFT(_collateralOft).token() == _collateral, "OftMismatch");
        }

        COLLATERAL_OFT = IOFT(_collateralOft);
    }

    /*//////////////////////////////////////////////////////////////
                BASEREMOTEINVENTORY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge underlying asset back to origin chain via LxLy
    /// @dev Burns the wrapped token; the origin receives the vbToken and
    ///      redeems it for the underlying during harvest.
    /// @param _amount Amount of asset to bridge back
    /// @return The amount bridged
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        // Approve bridge to spend our asset
        asset.forceApprove(address(LXLY_BRIDGE), _amount);

        // Bridge wrapped token back to origin chain
        LXLY_BRIDGE.bridgeAsset(
            uint32(uint256(REMOTE_ID)), // originNetworkId (Ethereum)
            REMOTE_COUNTERPART,
            _amount,
            address(asset),
            true, // forceUpdateGlobalExitRoot
            "" // permitData
        );

        return _amount;
    }

    /// @notice Bridge collateral back to origin chain via its LayerZero OFT,
    ///         or via the LxLy bridge when no OFT is configured.
    /// @param _amount Amount of collateral to bridge back
    /// @return The amount received on the origin chain
    function _bridgeCollateral(
        uint256 _amount
    ) internal virtual override returns (uint256) {
        if (address(COLLATERAL_OFT) != address(0)) {
            return
                _oftSend(
                    address(COLLATERAL_OFT),
                    ORIGIN_EID,
                    REMOTE_COUNTERPART,
                    _amount
                );
        }

        collateral.forceApprove(address(LXLY_BRIDGE), _amount);

        LXLY_BRIDGE.bridgeAsset(
            uint32(uint256(REMOTE_ID)), // originNetworkId (Ethereum)
            REMOTE_COUNTERPART,
            _amount,
            address(collateral),
            true, // forceUpdateGlobalExitRoot
            "" // permitData
        );

        return _amount;
    }

    /// @notice Send report to origin chain via LxLy
    /// @param data Encoded message data (totalAssets and timestamp)
    function _bridgeMessage(bytes memory data) internal override {
        LXLY_BRIDGE.bridgeMessage(
            uint32(uint256(REMOTE_ID)), // originNetworkId (Ethereum)
            REMOTE_COUNTERPART,
            true, // forceUpdateGlobalExitRoot
            data
        );
    }

    /*//////////////////////////////////////////////////////////////
                        LXLY MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle incoming bridge message (not used by remote inventory)
    /// @dev Remote inventory doesn't receive messages, only sends reports
    function onMessageReceived(
        address, // originAddress
        uint32, // originNetwork
        bytes calldata // data
    ) external payable override {
        revert("NotSupported");
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Rescue ETH held for LayerZero fees.
    function rescueETH(address _to, uint256 _amount) external onlyGovernance {
        _rescueETH(_to, _amount);
    }
}

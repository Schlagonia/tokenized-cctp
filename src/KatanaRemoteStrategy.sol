// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseRemote4626} from "./bases/BaseRemote4626.sol";
import {BaseLxLy} from "./bases/BaseLxLy.sol";

/// @title KatanaRemoteStrategy
/// @notice Remote strategy on Katana that receives bridged vbTokens and deploys to ERC4626 vault
/// @dev Receives assets via off-chain claims, deploys to vault, and reports back via LxLy bridge
contract KatanaRemoteStrategy is BaseRemote4626, BaseLxLy {
    using SafeERC20 for *;

    constructor(
        address _asset,
        address _governance,
        address _bridge,
        uint32 _originNetworkId,
        address _originCounterpart,
        address _vault
    )
        BaseRemote4626(
            _asset,
            _governance,
            bytes32(uint256(_originNetworkId)),
            _originCounterpart,
            _vault
        )
        BaseLxLy(_bridge)
    {}

    /*//////////////////////////////////////////////////////////////
                BASEREMOTESTRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets back to origin chain via LxLy
    /// @dev Uses bridgeAsset to send vbToken back to Ethereum
    /// @param _amount Amount of vbToken to bridge back
    /// @return The amount bridged
    function _bridgeAssets(
        uint256 _amount
    ) internal override returns (uint256) {
        // Approve bridge to spend our asset
        asset.forceApprove(address(LXLY_BRIDGE), _amount);

        // Bridge vbToken back to origin chain
        LXLY_BRIDGE.bridgeAsset(
            uint32(uint256(REMOTE_ID)), // originNetworkId (Ethereum)
            REMOTE_COUNTERPART,
            _amount,
            address(asset),
            false, // forceUpdateGlobalExitRoot
            "" // permitData
        );

        return _amount;
    }

    /// @notice Send profit/loss report to origin chain via LxLy
    /// @dev Uses bridgeMessage to send totalAssets back to origin strategy
    /// @param data Encoded message data (totalAssets)
    function _bridgeMessage(bytes memory data) internal override {
        LXLY_BRIDGE.bridgeMessage(
            uint32(uint256(REMOTE_ID)), // originNetworkId (Ethereum)
            REMOTE_COUNTERPART,
            false, // forceUpdateGlobalExitRoot
            data
        );
    }

    /*//////////////////////////////////////////////////////////////
                        LXLY MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle incoming bridge message (not used by remote strategy)
    /// @dev Remote strategies don't receive messages, only send reports
    function onMessageReceived(
        address, // originAddress
        uint32, // originNetwork
        bytes calldata // data
    ) external payable override {
        // Remote strategies don't process incoming messages
        // Only origin strategy receives messages from remote
        revert("NotSupported");
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
    ) external onlyGovernance {
        require(
            _token != address(asset) && _token != address(vault),
            "InvalidToken"
        );
        ERC20(_token).safeTransfer(_to, _amount);
    }
}

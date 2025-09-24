// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {RemoteStrategy} from "./RemoteStrategy.sol";
import {BaseCCTP} from "./BaseCCTP.sol";

/// @notice Strategy that bridges native USDC via CCTP to a destination chain
/// and tracks the remote deployed capital through periodic accounting updates.
contract Strategy is BaseHealthCheck, BaseCCTP {
    using SafeERC20 for ERC20;

    address public immutable DEPOSITER;

    uint256 public remoteAssets;

    constructor(
        address _asset,
        string memory _name,
        address _tokenMessenger,
        address _messageTransmitter,
        uint32 _remoteDomain,
        address _remoteCounterpart,
        address _depositer
    )
        BaseHealthCheck(_asset, _name)
        BaseCCTP(
            _tokenMessenger,
            _messageTransmitter,
            _remoteDomain,
            _remoteCounterpart
        )
    {
        require(_depositer != address(0), "ZeroAddress");

        DEPOSITER = _depositer;

        asset.forceApprove(_tokenMessenger, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        bytes memory hookData = abi.encode(nextRequestId, int256(_amount));

        nextRequestId++;

        TOKEN_MESSENGER.depositForBurnWithHook(
            _amount,
            REMOTE_DOMAIN,
            _addressToBytes32(REMOTE_COUNTERPART),
            address(asset),
            bytes32(0),
            0,
            FINALITY_THRESHOLD_FINALIZED,
            hookData
        );

        remoteAssets += _amount;
    }

    function _freeFunds(uint256) internal pure override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this)) + remoteAssets;
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    function availableWithdrawLimit(
        address /* _owner */
    ) public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        return _owner == DEPOSITER ? type(uint256).max : 0;
    }

    /*//////////////////////////////////////////////////////////////
                        CCTP MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    function _receiveMessage(int256 amount) internal virtual override {
        // RequestId should be unique id for each message.
        // amount will be either a profit/loss report or a withdrawal fufillment.
        // Example -100 would be for if 100 was bridged back from remote vault.
        // 10 would be for reporting 10 profit. -10 would be for reporting 10 loss.
        remoteAssets = uint256(int256(remoteAssets) + amount);
    }
}

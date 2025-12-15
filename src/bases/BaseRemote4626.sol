// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseRemoteStrategy} from "./BaseRemoteStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseRemote4626 is BaseRemoteStrategy {
    using SafeERC20 for *;

    /// @notice The ERC4626 vault where assets are deployed
    IERC4626 public immutable vault;

    constructor(
        address _asset,
        address _governance,
        bytes32 _remoteId,
        address _remoteCounterpart,
        address _vault
    ) BaseRemoteStrategy(_asset, _governance, _remoteId, _remoteCounterpart) {
        vault = IERC4626(_vault);
        require(vault.asset() == _asset, "wrong vault");

        asset.forceApprove(_vault, type(uint256).max);
    }

    function _pushFunds(
        uint256 _amount
    ) internal virtual override returns (uint256) {
        vault.deposit(
            Math.min(_amount, vault.maxDeposit(address(this))),
            address(this)
        );
        return _amount;
    }

    function _pullFunds(
        uint256 _amount
    ) internal virtual override returns (uint256) {
        return
            vault.redeem(
                Math.min(
                    vault.maxRedeem(address(this)),
                    vault.previewWithdraw(_amount)
                ),
                address(this),
                address(this)
            );
    }

    /// @notice Calculate assets deployed in vault
    function valueOfDeployedAssets() public view override returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }
}

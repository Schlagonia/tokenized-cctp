// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseAsyncRedemption} from "./BaseAsyncRedemption.sol";
import {IQueue, IWETH, IwstETH} from "../interfaces/IStethInterfaces.sol";

/// @notice Lido withdrawal-queue redemption layer.
/// @dev For a wstETH-collateral / WETH-asset inventory strategy: collateral is
///      unwrapped to stETH and redeemed 1:1 for ETH through the Lido queue,
///      then wrapped to WETH. Uses `collateral`/`asset` from the base so it is
///      not tied to a specific bridge.
abstract contract LidoRedemption is BaseAsyncRedemption {
    using SafeERC20 for ERC20;

    address internal constant STETH =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WITHDRAWAL_QUEUE =
        0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    function _initiateRedemption(
        uint256 _amount
    ) internal virtual override returns (uint256 id, uint256 pendingAssets) {
        pendingAssets = IwstETH(address(collateral)).unwrap(_amount);
        ERC20(STETH).forceApprove(WITHDRAWAL_QUEUE, pendingAssets);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = pendingAssets;

        id = IQueue(WITHDRAWAL_QUEUE).requestWithdrawals(
            amounts,
            address(this)
        )[0];
    }

    function _claimRedemption(
        uint256 _id
    ) internal virtual override returns (uint256 assets) {
        uint256 preBalance = balanceOfAsset();
        IQueue(WITHDRAWAL_QUEUE).claimWithdrawal(_id);
        if (address(this).balance > 0) {
            IWETH(address(asset)).deposit{value: address(this).balance}();
        }
        assets = balanceOfAsset() - preBalance;
    }

    /// @dev Also protect stETH held transiently between unwrap and queueing.
    function _isProtectedToken(
        address _token
    ) internal view virtual override returns (bool) {
        return super._isProtectedToken(_token) || _token == STETH;
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {KatanaInventoryStrategy} from "./KatanaInventoryStrategy.sol";
import {IQueue, IWETH, IwstETH} from "./interfaces/IStethInterfaces.sol";
import {KatanaHelpers} from "./libraries/KatanaHelpers.sol";

/// @title WstETHKatanaInventoryStrategy
/// @notice wstETH/WETH inventory strategy for Katana.
/// @dev WETH bridges via vbETH/LxLy and wstETH via the LxLy wrapped token (no
///      OFT). Collateral returning from Katana is redeemed 1:1 through the
///      Lido withdrawal queue: wstETH is unwrapped to stETH, redeemed for ETH,
///      and wrapped to WETH. Value is indeterminate while a redemption is
///      pending, so reports are blocked until it is claimed.
contract WstETHKatanaInventoryStrategy is KatanaInventoryStrategy {
    using SafeERC20 for ERC20;

    address internal constant STETH =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WITHDRAWAL_QUEUE =
        0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    event CooldownInitiated(uint256 indexed nftId, uint256 pendingAssets);

    event CooldownClaimed(uint256 indexed claimId, uint256 assets);

    constructor(
        string memory _name,
        address _oracle,
        address _exchange,
        address _remoteCounterpart
    )
        KatanaInventoryStrategy(
            KatanaHelpers.ETHEREUM_WETH,
            _name,
            WSTETH,
            _oracle,
            _exchange,
            KatanaHelpers.VB_WETH,
            address(0), // no OFT: wstETH bridges via LxLy
            _remoteCounterpart
        )
    {}

    /*//////////////////////////////////////////////////////////////
                        LIDO WITHDRAWAL QUEUE
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate stETH withdrawal through the Lido queue for 1:1
    ///         redemption.
    /// @param _amount Amount of wstETH to queue for withdrawal
    /// @return nftId Withdrawal request id
    function initiateCooldown(
        uint256 _amount
    ) external onlyManagement returns (uint256 nftId) {
        uint256 balance = balanceOfCollateral();
        if (_amount > balance) _amount = balance;
        require(_amount > 0, "ZeroAmount");

        uint256 pendingAssets = IwstETH(WSTETH).unwrap(_amount);
        ERC20(STETH).forceApprove(WITHDRAWAL_QUEUE, pendingAssets);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = pendingAssets;

        nftId = IQueue(WITHDRAWAL_QUEUE).requestWithdrawals(
            amounts,
            address(this)
        )[0];

        unchecked {
            pendingRedemptions += pendingAssets;
        }

        emit CooldownInitiated(nftId, pendingAssets);
    }

    /// @notice Claim ETH from a completed Lido withdrawal request.
    /// @param _claimId The withdrawal request id
    /// @return assets Amount of WETH received
    function claimCooldown(
        uint256 _claimId
    ) external payable onlyKeepers returns (uint256 assets) {
        uint256 preBalance = balanceOfAsset();
        IQueue(WITHDRAWAL_QUEUE).claimWithdrawal(_claimId);
        if (address(this).balance > 0) {
            IWETH(address(asset)).deposit{value: address(this).balance}();
        }
        assets = balanceOfAsset() - preBalance;

        if (assets >= pendingRedemptions) {
            delete pendingRedemptions;
        } else {
            unchecked {
                pendingRedemptions -= assets;
            }
        }

        emit CooldownClaimed(_claimId, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Value is indeterminate while a Lido redemption is pending, so
    ///      block reports until it is claimed (or written off via
    ///      zeroPendingRedemptions).
    function _harvestAndReport() internal override returns (uint256) {
        require(pendingRedemptions == 0, "pending");
        return super._harvestAndReport();
    }

    /// @dev Also protect stETH held transiently between unwrap and queueing.
    function _isProtectedToken(
        address _token
    ) internal view override returns (bool) {
        return super._isProtectedToken(_token) || _token == STETH;
    }
}

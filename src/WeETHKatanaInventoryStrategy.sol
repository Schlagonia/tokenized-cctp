// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {KatanaInventoryStrategy} from "./KatanaInventoryStrategy.sol";
import {BaseAsyncRedemption} from "./bases/BaseAsyncRedemption.sol";
import {EtherFiRedemption} from "./bases/EtherFiRedemption.sol";
import {KatanaHelpers} from "./libraries/KatanaHelpers.sol";

/// @title WeETHKatanaInventoryStrategy
/// @notice weETH/WETH inventory strategy for Katana.
/// @dev Composition of the Katana bridge base and the EtherFi redemption
///      add-on. Both WETH (via vbETH) and weETH bridge over the LxLy/Agglayer
///      canonical bridge as wrapped tokens — weETH on Katana is the
///      LxLy-wrapped token (0x9893...), not a LayerZero OFT — so no OFT is
///      configured. Collateral returning from Katana is redeemed for ETH
///      through the EtherFi withdrawal flow with pending-redemption accounting.
contract WeETHKatanaInventoryStrategy is
    KatanaInventoryStrategy,
    EtherFiRedemption
{
    address internal constant WEETH =
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    constructor(
        string memory _name,
        address _oracle,
        address _exchange,
        address _remoteCounterpart
    )
        KatanaInventoryStrategy(
            KatanaHelpers.ETHEREUM_WETH,
            _name,
            WEETH,
            _oracle,
            _exchange,
            KatanaHelpers.VB_WETH,
            address(0), // no OFT: weETH bridges via LxLy on Katana
            _remoteCounterpart
        )
    {}

    function _harvestAndReport()
        internal
        override(KatanaInventoryStrategy, BaseAsyncRedemption)
        returns (uint256)
    {
        return super._harvestAndReport();
    }

    function _isProtectedToken(
        address _token
    )
        internal
        view
        override(KatanaInventoryStrategy, EtherFiRedemption)
        returns (bool)
    {
        return super._isProtectedToken(_token);
    }
}

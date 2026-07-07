// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {KatanaInventoryStrategy} from "./KatanaInventoryStrategy.sol";
import {BaseAsyncRedemption} from "./bases/BaseAsyncRedemption.sol";
import {LidoRedemption} from "./bases/LidoRedemption.sol";
import {KatanaHelpers} from "./libraries/KatanaHelpers.sol";

/// @title WstETHKatanaInventoryStrategy
/// @notice wstETH/WETH inventory strategy for Katana.
/// @dev Composition of the Katana bridge base (WETH via vbETH/LxLy, wstETH via
///      the LxLy wrapped token — no OFT) and the Lido redemption add-on.
///      Collateral returning from Katana is redeemed 1:1 through the Lido
///      withdrawal queue with pending-redemption accounting.
contract WstETHKatanaInventoryStrategy is
    KatanaInventoryStrategy,
    LidoRedemption
{
    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

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
        override(KatanaInventoryStrategy, LidoRedemption)
        returns (bool)
    {
        return super._isProtectedToken(_token);
    }
}

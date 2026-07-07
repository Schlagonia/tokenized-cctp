// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IwstETH} from "../interfaces/IStethInterfaces.sol";

/// @title WstETHOracle
/// @notice Morpho-convention oracle pricing 1 wstETH in WETH terms, scaled
///         by 1e36, using the Lido wstETH/stETH exchange rate (1 stETH is
///         valued 1:1 with ETH, matching the withdrawal-queue redemption).
contract WstETHOracle {
    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    function price() external view returns (uint256) {
        // Both tokens are 18 decimals so the 1e36 scale reduces to
        // stEthPerWstEth * 1e18.
        return IwstETH(WSTETH).getStETHByWstETH(1e18) * 1e18;
    }
}

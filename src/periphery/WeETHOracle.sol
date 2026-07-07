// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IWeETH} from "../interfaces/IEtherFiInterfaces.sol";

/// @title WeETHOracle
/// @notice Morpho-convention oracle pricing 1 weETH in WETH terms, scaled by
///         1e36, using the EtherFi weETH/eETH rate (eETH valued 1:1 with ETH,
///         matching the EtherFi withdrawal redemption).
contract WeETHOracle {
    address internal constant WEETH =
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    function price() external view returns (uint256) {
        // Both tokens are 18 decimals so the 1e36 scale reduces to
        // eEthPerWeEth * 1e18.
        return IWeETH(WEETH).getEETHByWeETH(1e18) * 1e18;
    }
}

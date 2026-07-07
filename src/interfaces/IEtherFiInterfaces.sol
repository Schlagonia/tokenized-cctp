// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWeETH is IERC20 {
    function wrap(uint256 _eETHAmount) external returns (uint256);

    function unwrap(uint256 _weETHAmount) external returns (uint256);

    function getEETHByWeETH(
        uint256 _weETHAmount
    ) external view returns (uint256);

    function getWeETHByeETH(
        uint256 _eETHAmount
    ) external view returns (uint256);
}

interface ILiquidityPool {
    function requestWithdraw(
        address recipient,
        uint256 amount
    ) external returns (uint256);
}

interface IWithdrawRequestNFT {
    function claimWithdraw(uint256 tokenId) external;
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISteth is IERC20 {
    function submit(address) external payable returns (uint256);
}

interface IwstETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function getWstETHByStETH(
        uint256 _stETHAmount
    ) external view returns (uint256);

    function getStETHByWstETH(
        uint256 _wstETHAmount
    ) external view returns (uint256);
}

interface IQueue {
    function claimWithdrawal(uint256 _requestId) external;

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    function claimWithdrawals(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external;

    function getWithdrawalRequests(
        address
    ) external view returns (uint256[] memory);

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);
}

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseAsyncRedemption} from "./BaseAsyncRedemption.sol";
import {IWETH} from "../interfaces/IStethInterfaces.sol";
import {IWeETH, ILiquidityPool, IWithdrawRequestNFT} from "../interfaces/IEtherFiInterfaces.sol";

/// @notice EtherFi weETH withdrawal redemption layer.
/// @dev For a weETH-collateral / WETH-asset inventory strategy: collateral is
///      unwrapped to eETH and redeemed for ETH through the EtherFi liquidity
///      pool / withdraw-request NFT, then wrapped to WETH. Uses
///      `collateral`/`asset` from the base so it is not tied to a bridge.
abstract contract EtherFiRedemption is BaseAsyncRedemption {
    using SafeERC20 for ERC20;

    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant LIQUIDITY_POOL =
        0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address internal constant WITHDRAW_REQUEST_NFT =
        0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;

    function _initiateRedemption(
        uint256 _amount
    ) internal virtual override returns (uint256 id, uint256 pendingAssets) {
        // Unwrap weETH -> eETH (eETH is 1:1 with ETH at redemption).
        pendingAssets = IWeETH(address(collateral)).unwrap(_amount);
        ERC20(EETH).forceApprove(LIQUIDITY_POOL, pendingAssets);
        id = ILiquidityPool(LIQUIDITY_POOL).requestWithdraw(
            address(this),
            pendingAssets
        );
    }

    function _claimRedemption(
        uint256 _id
    ) internal virtual override returns (uint256 assets) {
        uint256 preBalance = balanceOfAsset();
        IWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(_id);
        if (address(this).balance > 0) {
            IWETH(address(asset)).deposit{value: address(this).balance}();
        }
        assets = balanceOfAsset() - preBalance;
    }

    /// @dev Also protect eETH held transiently between unwrap and request.
    function _isProtectedToken(
        address _token
    ) internal view virtual override returns (bool) {
        return super._isProtectedToken(_token) || _token == EETH;
    }

    /// @notice Accept the EtherFi withdraw-request NFT (minted via _safeMint).
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {KatanaInventoryStrategy} from "./KatanaInventoryStrategy.sol";
import {IWETH} from "./interfaces/IStethInterfaces.sol";
import {IWeETH, ILiquidityPool, IWithdrawRequestNFT} from "./interfaces/IEtherFiInterfaces.sol";
import {KatanaHelpers} from "./libraries/KatanaHelpers.sol";

/// @title WeETHKatanaInventoryStrategy
/// @notice weETH/WETH inventory strategy for Katana.
/// @dev Both WETH (via vbETH) and weETH bridge over the LxLy/Agglayer
///      canonical bridge — weETH on Katana is the LxLy-wrapped token
///      (0x9893...), not a LayerZero OFT — so no OFT is configured.
///      Collateral returning from Katana is redeemed for ETH through the
///      EtherFi withdrawal flow: weETH is unwrapped to eETH, redeemed via the
///      liquidity pool / withdraw-request NFT, and wrapped to WETH. Value is
///      indeterminate while a redemption is pending, so reports are blocked
///      until it is claimed.
contract WeETHKatanaInventoryStrategy is KatanaInventoryStrategy {
    using SafeERC20 for ERC20;

    address internal constant WEETH =
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant LIQUIDITY_POOL =
        0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address internal constant WITHDRAW_REQUEST_NFT =
        0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;

    event CooldownInitiated(uint256 indexed requestId, uint256 pendingAssets);

    event CooldownClaimed(uint256 indexed requestId, uint256 assets);

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

    /*//////////////////////////////////////////////////////////////
                        ETHERFI WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate an EtherFi withdrawal for weETH collateral.
    /// @param _amount Amount of weETH to queue for withdrawal
    /// @return requestId The EtherFi withdraw-request id
    function initiateCooldown(
        uint256 _amount
    ) external onlyManagement returns (uint256 requestId) {
        uint256 balance = balanceOfCollateral();
        if (_amount > balance) _amount = balance;
        require(_amount > 0, "ZeroAmount");

        // Unwrap weETH -> eETH (eETH is 1:1 with ETH at redemption).
        uint256 pendingAssets = IWeETH(WEETH).unwrap(_amount);
        ERC20(EETH).forceApprove(LIQUIDITY_POOL, pendingAssets);
        requestId = ILiquidityPool(LIQUIDITY_POOL).requestWithdraw(
            address(this),
            pendingAssets
        );

        unchecked {
            pendingRedemptions += pendingAssets;
        }

        emit CooldownInitiated(requestId, pendingAssets);
    }

    /// @notice Claim ETH from a completed EtherFi withdrawal request.
    /// @param _requestId The EtherFi withdraw-request id
    /// @return assets Amount of WETH received
    function claimCooldown(
        uint256 _requestId
    ) external payable onlyKeepers returns (uint256 assets) {
        uint256 preBalance = balanceOfAsset();
        IWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(_requestId);
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

        emit CooldownClaimed(_requestId, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Value is indeterminate while an EtherFi redemption is pending, so
    ///      block reports until it is claimed (or written off via
    ///      zeroPendingRedemptions).
    function _harvestAndReport() internal override returns (uint256) {
        require(pendingRedemptions == 0, "pending");
        return super._harvestAndReport();
    }

    /// @dev Also protect eETH held transiently between unwrap and request.
    function _isProtectedToken(
        address _token
    ) internal view override returns (bool) {
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

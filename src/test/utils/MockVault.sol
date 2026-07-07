// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title MockVault
/// @notice Minimal 1:1 ERC4626 vault for tests (with optional profit/loss).
contract MockVault is IERC4626 {
    ERC20 public immutable _asset;
    mapping(address => uint256) public shares;
    uint256 public totalShares;
    uint256 public totalAssetAmount;

    constructor(address asset_) {
        _asset = ERC20(asset_);
    }

    function addProfit(uint256 amount) external {
        totalAssetAmount += amount;
    }

    function simulateLoss(uint256 amount) external {
        totalAssetAmount = amount > totalAssetAmount
            ? 0
            : totalAssetAmount - amount;
    }

    function asset() external view override returns (address) {
        return address(_asset);
    }

    function totalAssets() external view override returns (uint256) {
        return totalAssetAmount;
    }

    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        if (totalAssetAmount == 0 || totalShares == 0) return assets;
        return (assets * totalShares) / totalAssetAmount;
    }

    function convertToAssets(
        uint256 _shares
    ) public view override returns (uint256) {
        if (totalShares == 0) return _shares;
        return (_shares * totalAssetAmount) / totalShares;
    }

    function maxDeposit(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(
        uint256 assets
    ) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external override returns (uint256 _shares) {
        _shares = convertToShares(assets);
        if (_shares == 0) _shares = assets;
        _asset.transferFrom(msg.sender, address(this), assets);
        shares[receiver] += _shares;
        totalShares += _shares;
        totalAssetAmount += assets;
    }

    function maxMint(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(
        uint256 _shares
    ) external view override returns (uint256) {
        return convertToAssets(_shares);
    }

    function mint(
        uint256 _shares,
        address receiver
    ) external override returns (uint256 assets) {
        assets = convertToAssets(_shares);
        if (assets == 0) assets = _shares;
        _asset.transferFrom(msg.sender, address(this), assets);
        shares[receiver] += _shares;
        totalShares += _shares;
        totalAssetAmount += assets;
    }

    function maxWithdraw(
        address owner
    ) external view override returns (uint256) {
        return convertToAssets(shares[owner]);
    }

    function previewWithdraw(
        uint256 assets
    ) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override returns (uint256 _shares) {
        _shares = convertToShares(assets);
        require(shares[owner] >= _shares, "insufficient shares");
        shares[owner] -= _shares;
        totalShares -= _shares;
        totalAssetAmount -= assets;
        _asset.transfer(receiver, assets);
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return shares[owner];
    }

    function previewRedeem(
        uint256 _shares
    ) external view override returns (uint256) {
        return convertToAssets(_shares);
    }

    function redeem(
        uint256 _shares,
        address receiver,
        address owner
    ) external override returns (uint256 assets) {
        require(shares[owner] >= _shares, "insufficient shares");
        assets = convertToAssets(_shares);
        shares[owner] -= _shares;
        totalShares -= _shares;
        totalAssetAmount -= assets;
        _asset.transfer(receiver, assets);
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return shares[account];
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(shares[msg.sender] >= amount, "insufficient shares");
        shares[msg.sender] -= amount;
        shares[to] += amount;
        return true;
    }

    function allowance(
        address,
        address
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(shares[from] >= amount, "insufficient shares");
        shares[from] -= amount;
        shares[to] += amount;
        return true;
    }

    function totalSupply() external view override returns (uint256) {
        return totalShares;
    }

    function name() external pure returns (string memory) {
        return "Mock Vault";
    }

    function symbol() external pure returns (string memory) {
        return "mVAULT";
    }

    function decimals() external view returns (uint8) {
        return _asset.decimals();
    }
}

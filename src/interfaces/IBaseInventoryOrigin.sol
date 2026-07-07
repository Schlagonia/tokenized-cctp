// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "./IBaseCrossChain.sol";
import {IOracle} from "./IOracle.sol";

/// @notice Interface for origin-chain inventory strategies
/// @dev Extends IBaseCrossChain with two-token inventory functionality
interface IBaseInventoryOrigin is IBaseCrossChain {
    event ExchangeSet(address indexed exchange);

    event OracleSet(address indexed oracle);

    event MaxSlippageSet(uint256 maxSlippageBps);

    event PendingRedemptionsZeroed(uint256 amount);

    /// @notice The collateral token bridged to the remote chain as inventory
    function collateral() external view returns (address);

    /// @notice Oracle pricing 1 collateral token in asset terms, 1e36 scaled
    function oracle() external view returns (IOracle);

    /// @notice Exchange used for default asset <-> collateral conversions
    function exchange() external view returns (address);

    /// @notice Max slippage vs the oracle price for conversions, in bps
    function maxSlippageBps() external view returns (uint256);

    /// @notice Asset value of collateral pending async redemption
    function pendingRedemptions() external view returns (uint256);

    /// @notice Convert underlying asset into collateral
    function convertToCollateral(uint256 _amount) external returns (uint256);

    /// @notice Convert collateral back into the underlying asset
    function convertToAsset(uint256 _amount) external returns (uint256);

    /// @notice Bridge underlying asset to the remote counterpart
    function bridgeAsset(uint256 _amount) external payable;

    /// @notice Bridge collateral to the remote counterpart
    function bridgeCollateral(uint256 _amount) external payable;

    /// @notice Set the exchange used for conversions
    function setExchange(address _exchange) external;

    /// @notice Set the collateral oracle
    function setOracle(address _oracle) external;

    /// @notice Set the max slippage for conversions in basis points
    function setMaxSlippageBps(uint256 _maxSlippageBps) external;

    /// @notice Write off any pending async redemptions
    function zeroPendingRedemptions() external;

    /// @notice Rescue tokens accidentally sent to this contract
    function rescue(address _token, address _to, uint256 _amount) external;

    /// @notice Collateral balance held locally
    function balanceOfCollateral() external view returns (uint256);

    /// @notice Value collateral in asset terms at the oracle price
    function collateralToAsset(uint256 _amount) external view returns (uint256);

    /// @notice Value asset in collateral terms at the oracle price
    function assetToCollateral(uint256 _amount) external view returns (uint256);
}

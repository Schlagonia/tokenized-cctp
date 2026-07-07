// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseCrossChain} from "./BaseCrossChain.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/// @notice Base contract for origin-chain inventory strategies.
/// @dev Holds both the underlying asset and a collateral token. Keepers can
///      convert between the two through a management-set exchange (bounded by
///      an oracle-derived slippage floor) and bridge either token to the fixed
///      remote counterpart, which serves as swap inventory for looper
///      strategies on the remote chain. Deposits never auto-bridge; the
///      direction of flows is management's choice.
abstract contract BaseInventoryOrigin is BaseCrossChain {
    using SafeERC20 for ERC20;

    event ExchangeSet(address indexed exchange);

    event OracleSet(address indexed oracle);

    event MaxSlippageSet(uint256 maxSlippageBps);

    event PendingRedemptionsZeroed(uint256 amount);

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    /// @notice The collateral token bridged to the remote chain as inventory.
    ERC20 public immutable collateral;

    /// @notice Oracle pricing 1 collateral token in asset terms, 1e36 scaled.
    IOracle public oracle;

    /// @notice Exchange used for default asset <-> collateral conversions.
    address public exchange;

    /// @notice Max slippage vs the oracle price for conversions, in bps.
    uint256 public maxSlippageBps;

    /// @notice Asset value of collateral pending async redemption.
    /// @dev Only used by subclasses with non-atomic redemption paths.
    uint256 public pendingRedemptions;

    constructor(
        address _asset,
        string memory _name,
        address _collateral,
        address _oracle,
        address _exchange,
        bytes32 _remoteId,
        uint256 _remoteChainId,
        address _remoteCounterpart
    )
        BaseCrossChain(
            _asset,
            _name,
            _remoteId,
            _remoteChainId,
            _remoteCounterpart
        )
    {
        require(_collateral != address(0), "ZeroAddress");
        require(_collateral != _asset, "SameToken");

        collateral = ERC20(_collateral);

        _setOracle(_oracle);
        _setExchange(_exchange);

        maxSlippageBps = 50;
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convert underlying asset into collateral.
    /// @dev Output is enforced to be at least the oracle-implied amount minus
    ///      `maxSlippageBps`, so keepers cannot select the minimum themselves.
    /// @param _amount Amount of asset to convert
    /// @return Amount of collateral received
    function convertToCollateral(
        uint256 _amount
    ) external virtual onlyKeepers returns (uint256) {
        _amount = Math.min(_amount, balanceOfAsset());
        require(_amount > 0, "ZeroAmount");
        return _convertAssetToCollateral(_amount);
    }

    /// @notice Convert collateral back into the underlying asset.
    /// @param _amount Amount of collateral to convert
    /// @return Amount of asset received
    function convertToAsset(
        uint256 _amount
    ) external virtual onlyKeepers returns (uint256) {
        _amount = Math.min(_amount, balanceOfCollateral());
        require(_amount > 0, "ZeroAmount");
        return _convertCollateralToAsset(_amount);
    }

    /// @notice Bridge underlying asset to the remote counterpart.
    /// @dev Payable so OFT-based implementations can be fee-funded per call.
    /// @param _amount Amount of asset to bridge
    function bridgeAsset(uint256 _amount) external payable virtual onlyKeepers {
        require(_amount > 0, "ZeroAmount");
        _creditRemote(_bridgeAssets(_amount));
    }

    /// @notice Bridge collateral to the remote counterpart.
    /// @dev The bridged amount is credited to remote assets at oracle value.
    /// @param _amount Amount of collateral to bridge
    function bridgeCollateral(
        uint256 _amount
    ) external payable virtual onlyKeepers {
        require(_amount > 0, "ZeroAmount");
        _creditRemote(collateralToAsset(_bridgeCollateral(_amount)));
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the exchange used for conversions.
    /// @dev Zeros approvals to the old exchange and max-approves the new one.
    function setExchange(address _exchange) external virtual onlyManagement {
        _setExchange(_exchange);
    }

    /// @notice Set the collateral oracle.
    function setOracle(address _oracle) external virtual onlyManagement {
        _setOracle(_oracle);
    }

    /// @notice Set the max slippage for conversions in basis points.
    function setMaxSlippageBps(
        uint256 _maxSlippageBps
    ) external virtual onlyManagement {
        require(_maxSlippageBps < MAX_BPS, "!bps");
        maxSlippageBps = _maxSlippageBps;
        emit MaxSlippageSet(_maxSlippageBps);
    }

    /// @notice Write off any pending async redemptions.
    /// @dev Escape hatch if a redemption queue position is written off or
    ///      settled outside the normal claim path.
    function zeroPendingRedemptions() external virtual onlyManagement {
        emit PendingRedemptionsZeroed(pendingRedemptions);
        pendingRedemptions = 0;
    }

    /// @notice Rescue tokens accidentally sent to this contract.
    /// @param _token Token to rescue
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external virtual onlyManagement {
        require(!_isProtectedToken(_token), "InvalidToken");
        ERC20(_token).safeTransfer(_to, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEWS
    //////////////////////////////////////////////////////////////*/

    function balanceOfCollateral() public view virtual returns (uint256) {
        return collateral.balanceOf(address(this));
    }

    /// @notice Value collateral in asset terms at the oracle price.
    function collateralToAsset(
        uint256 _amount
    ) public view virtual returns (uint256) {
        return Math.mulDiv(_amount, oracle.price(), ORACLE_PRICE_SCALE);
    }

    /// @notice Value asset in collateral terms at the oracle price.
    function assetToCollateral(
        uint256 _amount
    ) public view virtual returns (uint256) {
        return Math.mulDiv(_amount, ORACLE_PRICE_SCALE, oracle.price());
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Deposits are NOT auto-bridged. Keepers direct flows explicitly.
    function _deployFunds(uint256) internal virtual override {}

    /// @notice Reports total assets across both tokens and the remote chain.
    function _harvestAndReport() internal virtual override returns (uint256) {
        return
            balanceOfAsset() +
            collateralToAsset(balanceOfCollateral()) +
            pendingRedemptions +
            remoteAssets;
    }

    /// @dev Credit an outbound bridge to remote assets immediately and advance
    ///      the report watermark. Same semantics as BaseCrossChain._deployFunds.
    function _creditRemote(uint256 _assetValue) internal virtual {
        uint256 newRemoteAssets = remoteAssets + _assetValue;
        lastRemoteAssetsReport = block.timestamp;
        remoteAssets = newRemoteAssets;
        emit RemoteAssetsUpdated(newRemoteAssets);
    }

    /// @notice Default conversion via the exchange with an oracle floor.
    /// @dev Override for assets requiring custom mint/redeem paths.
    function _convertAssetToCollateral(
        uint256 _amount
    ) internal virtual returns (uint256) {
        uint256 minOut = (assetToCollateral(_amount) *
            (MAX_BPS - maxSlippageBps)) / MAX_BPS;
        return
            IExchange(exchange).exchange(
                address(asset),
                address(collateral),
                _amount,
                minOut
            );
    }

    /// @notice Default conversion via the exchange with an oracle floor.
    /// @dev Override for assets requiring async redemption (LST queues etc).
    ///      Async overrides should track `pendingRedemptions` in asset terms.
    function _convertCollateralToAsset(
        uint256 _amount
    ) internal virtual returns (uint256) {
        uint256 minOut = (collateralToAsset(_amount) *
            (MAX_BPS - maxSlippageBps)) / MAX_BPS;
        return
            IExchange(exchange).exchange(
                address(collateral),
                address(asset),
                _amount,
                minOut
            );
    }

    function _setExchange(address _exchange) internal virtual {
        require(_exchange != address(0), "ZeroAddress");

        address oldExchange = exchange;
        if (oldExchange != address(0)) {
            asset.forceApprove(oldExchange, 0);
            collateral.forceApprove(oldExchange, 0);
        }

        exchange = _exchange;
        asset.forceApprove(_exchange, type(uint256).max);
        collateral.forceApprove(_exchange, type(uint256).max);

        emit ExchangeSet(_exchange);
    }

    function _setOracle(address _oracle) internal virtual {
        require(_oracle != address(0), "ZeroAddress");
        require(IOracle(_oracle).price() > 0, "!price");
        oracle = IOracle(_oracle);
        emit OracleSet(_oracle);
    }

    /// @dev Tokens that can never be rescued.
    function _isProtectedToken(
        address _token
    ) internal view virtual returns (bool) {
        return _token == address(asset) || _token == address(collateral);
    }

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT METHODS TO IMPLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge collateral to the remote counterpart.
    /// @dev Implementation must handle bridge-specific transfer logic.
    /// @param _amount Amount of collateral to bridge
    /// @return The amount of collateral actually bridged
    function _bridgeCollateral(
        uint256 _amount
    ) internal virtual returns (uint256);
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {BaseRemoteStrategy} from "./BaseRemoteStrategy.sol";
import {IContextAwareExchange} from "../interfaces/IContextAwareExchange.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/// @notice Remote-chain inventory contract that IS the inventory swapper.
/// @dev Holds inventory of the underlying asset (loan token) and a collateral
///      token. Whitelisted looper strategies swap between the two at the
///      oracle price minus a discount through a whitelisted forwarder (the
///      chain's MetaExchange). Keepers can only move tokens back to the fixed
///      origin counterpart, so untrusted bots can rebalance inventory without
///      custody risk. `ORACLE.price()` follows Morpho's convention: one
///      collateral token quoted in loan token units, scaled by 1e36.
abstract contract BaseRemoteInventory is
    BaseRemoteStrategy,
    ReentrancyGuard,
    IContextAwareExchange
{
    using SafeERC20 for ERC20;

    event AllowedSet(address indexed account, bool allowed);

    event AllowedForwarderSet(address indexed forwarder, bool allowed);

    event DiscountSet(uint256 discount);

    event OracleSet(address indexed oracle);

    event CollateralBridged(uint256 indexed amount);

    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    /// @notice The collateral token held as swap inventory.
    ERC20 public immutable collateral;

    /// @notice Oracle pricing 1 collateral token in asset terms, 1e36 scaled.
    IOracle public oracle;

    /// @notice Discount applied to oracle quotes, in basis points.
    uint256 public discount;

    /// @notice Strategies (contexts) allowed to swap against the inventory.
    mapping(address => bool) public allowed;

    /// @notice Forwarders (MetaExchange) allowed to route swaps here.
    mapping(address => bool) public allowedForwarders;

    constructor(
        address _asset,
        address _collateral,
        address _oracle,
        uint256 _discount,
        address _governance,
        bytes32 _remoteId,
        address _remoteCounterpart
    ) BaseRemoteStrategy(_asset, _governance, _remoteId, _remoteCounterpart) {
        require(_collateral != address(0), "ZeroAddress");
        require(_collateral != _asset, "SameToken");

        collateral = ERC20(_collateral);

        _setOracle(_oracle);
        _setDiscount(_discount);
    }

    /*//////////////////////////////////////////////////////////////
                        INVENTORY SWAPPER
    //////////////////////////////////////////////////////////////*/

    function name() external pure virtual returns (string memory) {
        return "RemoteInventory";
    }

    /// @notice Swap against this contract's inventory at oracle price minus
    ///         the discount.
    /// @dev Only callable by whitelisted forwarders on behalf of whitelisted
    ///      contexts (the looper strategies).
    function exchangeWithContext(
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        address context
    ) external virtual nonReentrant returns (uint256 amountOut) {
        require(!isShutdown, "Shutdown");
        require(allowedForwarders[msg.sender], "!forwarder");
        require(allowed[context], "!allowed");

        if (amountIn == 0) return 0;

        ERC20(from).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = _exchangeFor(from, to, amountIn);
        require(amountOut >= amountOutMin, "!amountOut");
        ERC20(to).safeTransfer(msg.sender, amountOut);
    }

    function _exchangeFor(
        address from,
        address to,
        uint256 amountIn
    ) internal view virtual returns (uint256 amountOut) {
        uint256 rawAmountOut;
        uint256 price = oracle.price();
        require(price > 0, "!price");

        if (from == address(asset) && to == address(collateral)) {
            rawAmountOut = Math.mulDiv(amountIn, ORACLE_PRICE_SCALE, price);
        } else if (from == address(collateral) && to == address(asset)) {
            rawAmountOut = Math.mulDiv(amountIn, price, ORACLE_PRICE_SCALE);
        } else {
            revert("!pair");
        }

        amountOut = Math.mulDiv(rawAmountOut, MAX_BPS - discount, MAX_BPS);
        require(amountOut > 0, "!amountOut");
        require(amountOut <= ERC20(to).balanceOf(address(this)), "!inventory");
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge collateral back to the origin counterpart and report.
    /// @dev The underlying asset is bridged home via the inherited
    ///      processWithdrawal(). Payable so OFT fees can be funded per call.
    /// @param _amount Amount of collateral to bridge
    function bridgeCollateral(
        uint256 _amount
    ) external payable virtual onlyKeepers isReady {
        _amount = Math.min(_amount, balanceOfCollateral());
        require(_amount > 0, "ZeroAmount");

        uint256 bridged = _bridgeCollateral(_amount);

        emit CollateralBridged(bridged);

        // Send a report of the now current assets as well so accounting is
        // correct on the origin side.
        uint256 _totalAssets = totalAssets();

        bytes memory messageBody = abi.encode(_totalAssets, block.timestamp);
        _bridgeMessage(messageBody);

        emit Reported(_totalAssets);
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the discount applied to oracle quotes in basis points.
    function setDiscount(uint256 _discount) external virtual onlyGovernance {
        _setDiscount(_discount);
    }

    /// @notice Allow or disallow a strategy (context) to swap.
    function setAllowed(
        address _account,
        bool _isAllowed
    ) external virtual onlyGovernance {
        require(_account != address(0), "ZeroAddress");
        allowed[_account] = _isAllowed;
        emit AllowedSet(_account, _isAllowed);
    }

    /// @notice Allow or disallow a forwarder (MetaExchange) to route swaps.
    function setAllowedForwarder(
        address _forwarder,
        bool _isAllowed
    ) external virtual onlyGovernance {
        require(_forwarder != address(0), "ZeroAddress");
        allowedForwarders[_forwarder] = _isAllowed;
        emit AllowedForwarderSet(_forwarder, _isAllowed);
    }

    /// @notice Set the collateral oracle.
    function setOracle(address _oracle) external virtual onlyGovernance {
        _setOracle(_oracle);
    }

    /// @notice Rescue tokens accidentally sent to this contract.
    /// @dev Inventory tokens can never be rescued -- keepers and governance
    ///      can only move them along the bridge corridor.
    /// @param _token Token to rescue
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external virtual onlyGovernance {
        require(!_isProtectedToken(_token), "InvalidToken");
        ERC20(_token).safeTransfer(_to, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                    BASEREMOTESTRATEGY PLUMBING
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

    /// @notice The collateral inventory valued in asset terms.
    /// @dev Folded into totalAssets()/report() by BaseRemoteStrategy.
    function valueOfDeployedAssets()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return collateralToAsset(balanceOfCollateral());
    }

    /// @dev Idle tokens ARE the inventory. There is no vault to push to.
    function _pushFunds(uint256) internal virtual override returns (uint256) {
        return 0;
    }

    /// @dev Collateral cannot be atomically converted to asset here.
    ///      processWithdrawal() therefore caps to the loose asset balance.
    function _pullFunds(uint256) internal virtual override returns (uint256) {
        return 0;
    }

    /// @dev Nothing to tend.
    function _tendTrigger() internal view virtual override returns (bool) {
        return false;
    }

    /// @notice Tokens that can never be rescued or auctioned.
    function protectedTokens()
        public
        view
        virtual
        override
        returns (address[] memory _protectedTokens)
    {
        _protectedTokens = new address[](2);
        _protectedTokens[0] = address(asset);
        _protectedTokens[1] = address(collateral);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SETTERS
    //////////////////////////////////////////////////////////////*/

    function _setDiscount(uint256 _discount) internal virtual {
        require(_discount < MAX_BPS, "!discount");
        discount = _discount;
        emit DiscountSet(_discount);
    }

    function _setOracle(address _oracle) internal virtual {
        require(_oracle != address(0), "ZeroAddress");
        require(IOracle(_oracle).price() > 0, "!price");
        oracle = IOracle(_oracle);
        emit OracleSet(_oracle);
    }

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT METHODS TO IMPLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge collateral back to the origin counterpart.
    /// @dev Implementation must handle bridge-specific transfer logic.
    /// @param _amount Amount of collateral to bridge
    /// @return The amount of collateral actually bridged
    function _bridgeCollateral(
        uint256 _amount
    ) internal virtual returns (uint256);
}

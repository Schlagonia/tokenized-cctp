// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {KatanaInventoryStrategy} from "../../KatanaInventoryStrategy.sol";
import {KatanaRemoteInventory} from "../../KatanaRemoteInventory.sol";
import {KatanaHelpers} from "../../libraries/KatanaHelpers.sol";
import {IKatanaInventoryStrategy} from "../../interfaces/IKatanaInventoryStrategy.sol";
import {IVaultBridgeToken} from "../../interfaces/lxly/IVaultBridgeToken.sol";
import {IPolygonZkEVMBridgeV2} from "../../interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IContextAwareExchange} from "../../interfaces/IContextAwareExchange.sol";
import {IOracle} from "../../interfaces/IOracle.sol";

import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

/// @title KatanaInventorySetup
/// @notice Test setup for the Katana inventory strategy pair
/// @dev Requires BOTH ETH_RPC_URL and KAT_RPC_URL environment variables.
///      Uses real USDC/stcUSD/oracles/OFTs/bridge on both forks; only the
///      mainnet exchange and the Katana forwarder (MetaExchange stand-in)
///      are mocks.
contract KatanaInventorySetup is Test, IEvents {
    /*//////////////////////////////////////////////////////////////
                            CONTRACT INSTANCES
    //////////////////////////////////////////////////////////////*/

    /// @notice Origin strategy on Ethereum (unified interface)
    IKatanaInventoryStrategy public strategy;

    /// @notice Remote inventory swapper on Katana
    KatanaRemoteInventory public remoteInventory;

    /// @notice Mock exchange on Ethereum (oracle-priced, holds inventory)
    MockExchange public exchange;

    /// @notice Mock MetaExchange forwarder on Katana
    MockForwarder public forwarder;

    /*//////////////////////////////////////////////////////////////
                            TOKEN CONTRACTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Main asset (USDC on Ethereum)
    ERC20 public asset;

    /// @notice Collateral (stcUSD on Ethereum)
    ERC20 public collateral;

    /// @notice VaultBridgeToken for wrapping and bridging USDC
    IVaultBridgeToken public vbToken;

    /// @notice LxLy unified bridge
    IPolygonZkEVMBridgeV2 public lxlyBridge;

    /*//////////////////////////////////////////////////////////////
                            FORK IDS - BOTH REQUIRED
    //////////////////////////////////////////////////////////////*/

    uint256 public ethFork;
    uint256 public katFork;

    /*//////////////////////////////////////////////////////////////
                            KEY ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address public constant UNIFIED_BRIDGE = KatanaHelpers.UNIFIED_BRIDGE;
    address public constant VB_USDC = KatanaHelpers.VB_USDC;
    address public constant USDC = KatanaHelpers.ETHEREUM_USDC;

    /// @notice stcUSD (same vanity address on Ethereum and Katana)
    address public constant STCUSD = 0x88887bE419578051FF9F4eb6C858A951921D8888;

    /// @notice stcUSD LayerZero OFT adapter (lockbox) on Ethereum
    address public constant STCUSD_OFT_ADAPTER =
        0x983AEAaA0d0426839158435C43725EA7F45d4137;

    /// @notice stcUSD/USDC Morpho-convention oracle on Ethereum
    address public constant STCUSD_ORACLE_ETH =
        0x8E3386B2f6084eB1B0988070c3d826995BD175c0;

    /// @notice stcUSD/USDC Morpho-convention oracle on Katana
    address public constant STCUSD_ORACLE_KAT =
        0x832AEC697F9031709281e29ACb4fB69b1E3A6f7a;

    /// @notice Bridged USDC (wrapped vbUSDC) on Katana
    address public constant KATANA_USDC =
        0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36;

    /// @notice stcUSD on Katana (the token IS the OFT)
    address public constant KATANA_STCUSD = STCUSD;

    uint32 public constant ETHEREUM_NETWORK_ID =
        KatanaHelpers.ETHEREUM_NETWORK_ID;
    uint32 public constant KATANA_NETWORK_ID = KatanaHelpers.KATANA_NETWORK_ID;

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    /*//////////////////////////////////////////////////////////////
                            ROLE ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);
    address public depositor = address(6);
    address public governance = address(7);

    /// @notice Looper strategy stand-in (whitelisted swap context)
    address public looper = address(11);

    /*//////////////////////////////////////////////////////////////
                            FACTORY & CONFIG
    //////////////////////////////////////////////////////////////*/

    address public factory;

    uint256 public decimals;

    uint256 public MAX_BPS = 10_000;

    /// @notice Default remote swapper discount (bps)
    uint256 public discount = 50;

    uint256 public maxFuzzAmount = 1_000_000e6;
    uint256 public minFuzzAmount = 10_000;

    uint256 public profitMaxUnlockTime = 10 days;

    /*//////////////////////////////////////////////////////////////
                            FORK MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier useEthFork() {
        vm.selectFork(ethFork);
        _;
    }

    modifier useKatFork() {
        vm.selectFork(katFork);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        string memory katRpc = vm.envString("KAT_RPC_URL");

        require(
            bytes(ethRpc).length > 0,
            "ETH_RPC_URL environment variable is required"
        );
        require(
            bytes(katRpc).length > 0,
            "KAT_RPC_URL environment variable is required"
        );

        ethFork = vm.createFork(ethRpc);
        katFork = vm.createFork(katRpc);

        vm.selectFork(ethFork);

        asset = ERC20(USDC);
        collateral = ERC20(STCUSD);
        vbToken = IVaultBridgeToken(VB_USDC);
        lxlyBridge = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE);

        decimals = asset.decimals();

        _deployContracts();

        _labelAddresses();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deployContracts() internal {
        // First deploy the remote inventory on the Katana fork
        vm.selectFork(katFork);
        _deployKatanaContracts();

        // Then deploy the origin strategy on the Ethereum fork
        vm.selectFork(ethFork);
        _deployEthereumContracts();
    }

    function _deployKatanaContracts() internal {
        // Use placeholder for origin counterpart - production deploys use
        // nonce prediction so both sides know each other.
        address originCounterpartPlaceholder = address(0xDEAD);

        remoteInventory = new KatanaRemoteInventory(
            KATANA_USDC,
            KATANA_STCUSD,
            STCUSD_ORACLE_KAT,
            discount,
            governance,
            KATANA_STCUSD, // stcUSD itself is the OFT on Katana
            originCounterpartPlaceholder
        );

        vm.prank(governance);
        remoteInventory.setKeeper(keeper);

        // MetaExchange stand-in
        forwarder = new MockForwarder();

        vm.prank(governance);
        remoteInventory.setAllowedForwarder(address(forwarder), true);

        vm.prank(governance);
        remoteInventory.setAllowed(looper, true);

        // ETH for LayerZero fees on collateral bridging
        vm.deal(address(remoteInventory), 10 ether);
    }

    function _deployEthereumContracts() internal {
        // Oracle-priced mock exchange holding both tokens
        exchange = new MockExchange(USDC, STCUSD, STCUSD_ORACLE_ETH);

        // Fund the mock exchange inventory
        deal(USDC, address(exchange), 10_000_000e6);
        deal(STCUSD, address(exchange), 10_000_000e18);

        strategy = IKatanaInventoryStrategy(
            address(
                new KatanaInventoryStrategy(
                    USDC,
                    "Katana stcUSD Inventory",
                    STCUSD,
                    STCUSD_ORACLE_ETH,
                    address(exchange),
                    VB_USDC,
                    STCUSD_OFT_ADAPTER,
                    address(remoteInventory)
                )
            )
        );

        address currentManagement = strategy.management();

        vm.prank(currentManagement);
        strategy.setPendingManagement(management);

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(management);
        strategy.setKeeper(keeper);

        // Deposits are closed by default; whitelist the treasury depositor
        vm.prank(management);
        strategy.setAllowed(depositor, true);

        // Tolerate small oracle divergence between the two chains
        vm.prank(management);
        strategy.setLossLimitRatio(100);

        factory = strategy.FACTORY();

        // ETH for LayerZero fees on collateral bridging
        vm.deal(address(strategy), 10 ether);
    }

    function _labelAddresses() internal {
        vm.label(keeper, "keeper");
        vm.label(address(asset), "USDC");
        vm.label(STCUSD, "stcUSD");
        vm.label(STCUSD_OFT_ADAPTER, "stcUSD-OFT-Adapter");
        vm.label(management, "management");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(depositor, "depositor");
        vm.label(governance, "governance");
        vm.label(emergencyAdmin, "emergencyAdmin");
        vm.label(looper, "looper");
        vm.label(UNIFIED_BRIDGE, "LXLY_BRIDGE");
        vm.label(VB_USDC, "VB_USDC");
        vm.label(KATANA_USDC, "KatanaUSDC");
        vm.label(address(strategy), "KatanaInventoryStrategy");
        vm.label(address(remoteInventory), "KatanaRemoteInventory");
        vm.label(address(exchange), "MockExchange");
        vm.label(address(forwarder), "MockForwarder");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositIntoStrategy(
        IKatanaInventoryStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IKatanaInventoryStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    /// @notice Simulate a report message from Katana to Ethereum
    function simulateBridgeMessage(uint256 totalAssets) public {
        vm.selectFork(ethFork);
        simulateBridgeMessageAt(
            totalAssets,
            strategy.lastRemoteAssetsReport() + 1
        );
    }

    function simulateBridgeMessageAt(
        uint256 totalAssets,
        uint256 timestamp
    ) public {
        vm.selectFork(ethFork);

        bytes memory data = abi.encode(totalAssets, timestamp);

        vm.prank(UNIFIED_BRIDGE);
        strategy.onMessageReceived(
            address(remoteInventory),
            KATANA_NETWORK_ID,
            data
        );
    }

    /// @notice Simulate bridged tokens arriving on the Katana side
    function simulateArrivalOnKatana(address _token, uint256 _amount) public {
        vm.selectFork(katFork);
        airdrop(ERC20(_token), address(remoteInventory), _amount);
    }

    /// @notice Simulate bridged tokens arriving back on the Ethereum side
    /// @dev The USDC return path delivers vbUSDC, the collateral path stcUSD.
    function simulateArrivalOnEthereum(address _token, uint256 _amount) public {
        vm.selectFork(ethFork);
        airdrop(ERC20(_token), address(strategy), _amount);
    }

    /// @notice Simulate the USDC return path by minting real vbUSDC shares
    ///         to the strategy (what an LxLy claim would deliver).
    function simulateVbUsdcArrival(uint256 _amount) public {
        vm.selectFork(ethFork);
        airdrop(asset, address(this), _amount);
        IERC20(USDC).approve(VB_USDC, _amount);
        vbToken.deposit(_amount, address(strategy));
    }

    /// @notice Swap against the remote inventory as the looper would
    function looperSwap(
        address _from,
        address _to,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        vm.selectFork(katFork);

        airdrop(ERC20(_from), looper, _amountIn);

        vm.prank(looper);
        ERC20(_from).approve(address(forwarder), _amountIn);

        vm.prank(looper);
        amountOut = forwarder.exchange(
            address(remoteInventory),
            _from,
            _to,
            _amountIn,
            0
        );
    }

    /// @notice Live estimate of origin total assets across both tokens
    function estimatedTotalAssets() public view returns (uint256) {
        return
            strategy.balanceOfAsset() +
            strategy.collateralToAsset(strategy.balanceOfCollateral()) +
            strategy.valueOfVault() +
            strategy.pendingRedemptions() +
            strategy.remoteAssets();
    }

    /// @notice Assert reported total assets match the live estimate
    function checkInventoryInvariant() public {
        vm.selectFork(ethFork);
        assertApproxEqAbs(
            strategy.totalAssets(),
            estimatedTotalAssets(),
            // Allow rounding dust from oracle math
            1e6,
            "!invariant"
        );
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    /// @notice Value collateral in asset terms with a given oracle
    function oracleValue(
        address _oracle,
        uint256 _collateralAmount
    ) public view returns (uint256) {
        return
            Math.mulDiv(
                _collateralAmount,
                IOracle(_oracle).price(),
                ORACLE_PRICE_SCALE
            );
    }
}

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

/// @title MockExchange
/// @notice Oracle-priced IExchange venue holding its own inventory.
/// @dev Mimics the looper MetaExchange surface. A settable `skimBps` allows
///      simulating slippage to test the strategy's oracle floor.
contract MockExchange {
    using SafeERC20 for ERC20;

    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    ERC20 public immutable loanToken;
    ERC20 public immutable collateralToken;
    IOracle public immutable oracle;

    uint256 public skimBps;

    constructor(address _loanToken, address _collateralToken, address _oracle) {
        loanToken = ERC20(_loanToken);
        collateralToken = ERC20(_collateralToken);
        oracle = IOracle(_oracle);
    }

    function name() external pure returns (string memory) {
        return "MockExchange";
    }

    function setSkim(uint256 _skimBps) external {
        skimBps = _skimBps;
    }

    function exchange(
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut) {
        ERC20(from).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 price = oracle.price();

        if (from == address(loanToken) && to == address(collateralToken)) {
            amountOut = Math.mulDiv(amountIn, ORACLE_PRICE_SCALE, price);
        } else if (
            from == address(collateralToken) && to == address(loanToken)
        ) {
            amountOut = Math.mulDiv(amountIn, price, ORACLE_PRICE_SCALE);
        } else {
            revert("!pair");
        }

        amountOut = (amountOut * (MAX_BPS - skimBps)) / MAX_BPS;
        require(amountOut >= amountOutMin, "slippage");

        ERC20(to).safeTransfer(msg.sender, amountOut);
    }
}

/// @title MockForwarder
/// @notice Minimal MetaExchange stand-in: pulls from the caller, forwards to
///         a context-aware swapper with the caller as context.
contract MockForwarder {
    using SafeERC20 for ERC20;

    function exchange(
        address swapper,
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut) {
        ERC20(from).safeTransferFrom(msg.sender, address(this), amountIn);
        ERC20(from).forceApprove(swapper, amountIn);

        amountOut = IContextAwareExchange(swapper).exchangeWithContext(
            from,
            to,
            amountIn,
            amountOutMin,
            msg.sender
        );

        ERC20(to).safeTransfer(msg.sender, amountOut);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {KatanaStrategy} from "../../KatanaStrategy.sol";
import {KatanaRemoteStrategy} from "../../KatanaRemoteStrategy.sol";
import {KatanaHelpers} from "../../libraries/KatanaHelpers.sol";
import {IVaultBridgeToken} from "../../interfaces/lxly/IVaultBridgeToken.sol";
import {IPolygonZkEVMBridgeV2} from "../../interfaces/lxly/IPolygonZkEVMBridgeV2.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract KatanaSetup is Test, IEvents {
    // Contract instances
    KatanaStrategy public strategy;
    KatanaRemoteStrategy public remoteStrategy;

    // ITokenizedStrategy interface for accessing ERC4626 and management functions
    ITokenizedStrategy public tokenizedStrategy;

    // Token contracts
    ERC20 public asset;
    IVaultBridgeToken public vbToken;

    // Bridge contracts
    IPolygonZkEVMBridgeV2 public lxlyBridge;

    // Fork IDs
    uint256 public ethFork;
    uint256 public katFork;
    bool public hasKatanaFork;

    // Key addresses from KatanaHelpers
    address public constant UNIFIED_BRIDGE = KatanaHelpers.UNIFIED_BRIDGE;
    address public constant VB_USDC = KatanaHelpers.VB_USDC;
    address public constant VB_WETH = KatanaHelpers.VB_WETH;
    address public constant USDC = KatanaHelpers.ETHEREUM_USDC;
    address public constant WETH = KatanaHelpers.ETHEREUM_WETH;

    // Network IDs
    uint32 public constant ETHEREUM_NETWORK_ID =
        KatanaHelpers.ETHEREUM_NETWORK_ID;
    uint32 public constant KATANA_NETWORK_ID = KatanaHelpers.KATANA_NETWORK_ID;

    // Addresses for different roles
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);
    address public depositor = address(6);
    address public governance = address(7);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz bounds
    uint256 public maxFuzzAmount = 1_000_000e6;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time
    uint256 public profitMaxUnlockTime = 10 days;

    // USDC whales for funding tests
    address public constant ETH_USDC_WHALE =
        0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    // Mock vault on Katana (we'll deploy a mock or use existing)
    IERC4626 public remoteVault;

    // Fork modifiers
    modifier useEthFork() {
        vm.selectFork(ethFork);
        _;
    }

    modifier useKatFork() {
        require(hasKatanaFork, "Katana fork not available");
        vm.selectFork(katFork);
        _;
    }

    function setUp() public virtual {
        // Create Ethereum fork
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        ethFork = vm.createFork(ethRpc);

        // Try to create Katana fork if RPC is available
        try vm.envString("KAT_RPC_URL") returns (string memory katRpc) {
            if (bytes(katRpc).length > 0) {
                katFork = vm.createFork(katRpc);
                hasKatanaFork = true;
            }
        } catch {
            hasKatanaFork = false;
        }

        // Start with Ethereum fork
        vm.selectFork(ethFork);

        // Set asset to USDC
        asset = ERC20(USDC);
        vbToken = IVaultBridgeToken(VB_USDC);
        lxlyBridge = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE);

        // Set decimals
        decimals = asset.decimals();

        // Deploy main strategy (includes remote strategy deployment)
        _deployMainStrategy();

        // Label addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "USDC");
        vm.label(management, "management");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(depositor, "depositor");
        vm.label(governance, "governance");
        vm.label(emergencyAdmin, "emergencyAdmin");
        vm.label(UNIFIED_BRIDGE, "LXLY_BRIDGE");
        vm.label(VB_USDC, "VB_USDC");
        vm.label(address(strategy), "KatanaStrategy");
        vm.label(address(remoteStrategy), "KatanaRemoteStrategy");
    }

    function _deployMainStrategy() internal {
        vm.selectFork(ethFork);

        // Deploy remote strategy first so we have the correct address
        _deployRemoteStrategyFirst();

        strategy = new KatanaStrategy(
            USDC,
            "Katana USDC Strategy",
            VB_USDC,
            UNIFIED_BRIDGE,
            KATANA_NETWORK_ID,
            address(remoteStrategy),
            depositor
        );

        // Configure strategy through ITokenizedStrategy interface
        // The management functions are on the TokenizedStrategy proxy
        tokenizedStrategy = ITokenizedStrategy(address(strategy));

        // Get the current management (deployer) to set pending management
        address currentManagement = tokenizedStrategy.management();

        vm.prank(currentManagement);
        tokenizedStrategy.setPendingManagement(management);

        vm.prank(management);
        tokenizedStrategy.acceptManagement();

        vm.prank(management);
        tokenizedStrategy.setKeeper(keeper);

        factory = tokenizedStrategy.FACTORY();

        // Now update remote strategy with correct origin counterpart
        // This simulates the deployment order: remote first, then origin
        // Note: In a real deployment, we'd use CREATE2/CREATE3 for deterministic addresses
    }

    function _deployRemoteStrategyFirst() internal {
        // For testing, we deploy the mock vault and remote strategy first
        // so that we have the address to use in the main strategy
        vm.selectFork(ethFork);

        // Deploy a mock vault for testing
        remoteVault = IERC4626(_deployMockVault());

        // Use a placeholder for origin counterpart - will be updated after main strategy deployment
        // In real deployment, CREATE3 would give us deterministic addresses
        address originCounterpartPlaceholder = address(0xDEAD);

        remoteStrategy = new KatanaRemoteStrategy(
            address(asset),
            governance,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            originCounterpartPlaceholder,
            address(remoteVault)
        );

        // Set keeper
        vm.prank(governance);
        remoteStrategy.setKeeper(keeper, true);
    }

    function _deployMockVault() internal returns (address) {
        // Deploy a simple mock ERC4626 vault for testing
        MockVault mockVault = new MockVault(address(asset));
        return address(mockVault);
    }

    function depositIntoStrategy(
        KatanaStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        ITokenizedStrategy(address(_strategy)).deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        KatanaStrategy _strategy,
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

    function airdropUSDC(address _to, uint256 _amount) public {
        deal(USDC, _to, IERC20(USDC).balanceOf(_to) + _amount);
    }

    /// @notice Simulate a bridge message from Katana to Ethereum
    /// @param totalAssets The total assets reported by remote strategy
    function simulateBridgeMessage(uint256 totalAssets) public {
        vm.selectFork(ethFork);

        bytes memory data = abi.encode(totalAssets);

        // Prank as the bridge to call onMessageReceived
        vm.prank(UNIFIED_BRIDGE);
        strategy.onMessageReceived(
            address(remoteStrategy),
            KATANA_NETWORK_ID,
            data
        );
    }

    /// @notice Calculate remote assets tracked by strategy
    function calculateRemoteAssets(
        KatanaStrategy _strategy
    ) public view returns (uint256) {
        return _strategy.remoteAssets();
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setPerformanceFee(
            _performanceFee
        );
    }
}

/// @notice Simple mock ERC4626 vault for testing
contract MockVault is IERC4626 {
    ERC20 public immutable _asset;
    mapping(address => uint256) public shares;
    uint256 public totalShares;
    uint256 public totalAssetAmount;

    constructor(address asset_) {
        _asset = ERC20(asset_);
    }

    /// @notice Add profit to the vault (for testing)
    function addProfit(uint256 amount) external {
        totalAssetAmount += amount;
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

    // ERC20 functions for shares
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

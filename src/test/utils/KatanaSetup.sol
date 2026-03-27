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
import {IKatanaStrategy} from "../../interfaces/IKatanaStrategy.sol";
import {IVaultBridgeToken} from "../../interfaces/lxly/IVaultBridgeToken.sol";
import {IPolygonZkEVMBridgeV2} from "../../interfaces/lxly/IPolygonZkEVMBridgeV2.sol";

import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

/// @title KatanaSetup
/// @notice Test setup for Katana strategy tests
/// @dev Requires BOTH ETH_RPC_URL and KAT_RPC_URL environment variables
///      Tests will fail if either RPC URL is not set - no fallback
contract KatanaSetup is Test, IEvents {
    /*//////////////////////////////////////////////////////////////
                            CONTRACT INSTANCES
    //////////////////////////////////////////////////////////////*/

    /// @notice Main strategy on Ethereum (unified interface for all functions)
    IKatanaStrategy public strategy;

    /// @notice Remote strategy on Katana
    KatanaRemoteStrategy public remoteStrategy;

    /*//////////////////////////////////////////////////////////////
                            TOKEN CONTRACTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Main asset (USDC on Ethereum)
    ERC20 public asset;

    /// @notice VaultBridgeToken for wrapping and bridging
    IVaultBridgeToken public vbToken;

    /// @notice LxLy unified bridge
    IPolygonZkEVMBridgeV2 public lxlyBridge;

    /*//////////////////////////////////////////////////////////////
                            FORK IDS - BOTH REQUIRED
    //////////////////////////////////////////////////////////////*/

    /// @notice Ethereum mainnet fork ID
    uint256 public ethFork;

    /// @notice Katana L2 fork ID
    uint256 public katFork;

    /*//////////////////////////////////////////////////////////////
                            KEY ADDRESSES FROM KATANAHELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unified Bridge address (same on all chains)
    address public constant UNIFIED_BRIDGE = KatanaHelpers.UNIFIED_BRIDGE;

    /// @notice VaultBridgeToken for USDC on Ethereum
    address public constant VB_USDC = KatanaHelpers.VB_USDC;

    /// @notice VaultBridgeToken for WETH on Ethereum
    address public constant VB_WETH = KatanaHelpers.VB_WETH;

    /// @notice USDC on Ethereum mainnet
    address public constant USDC = KatanaHelpers.ETHEREUM_USDC;

    /// @notice WETH on Ethereum mainnet
    address public constant WETH = KatanaHelpers.ETHEREUM_WETH;

    /*//////////////////////////////////////////////////////////////
                            NETWORK IDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ethereum network ID (0)
    uint32 public constant ETHEREUM_NETWORK_ID =
        KatanaHelpers.ETHEREUM_NETWORK_ID;

    /// @notice Katana network ID (20)
    uint32 public constant KATANA_NETWORK_ID = KatanaHelpers.KATANA_NETWORK_ID;

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

    /*//////////////////////////////////////////////////////////////
                            FACTORY & CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the real deployed TokenizedStrategy Factory
    address public factory;

    /// @notice Asset decimals
    uint256 public decimals;

    /// @notice Max basis points
    uint256 public MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////////
                            FUZZ BOUNDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum fuzz amount (1M USDC)
    uint256 public maxFuzzAmount = 1_000_000e6;

    /// @notice Minimum fuzz amount ($0.01 worth)
    uint256 public minFuzzAmount = 10_000;

    /// @notice Default profit max unlock time
    uint256 public profitMaxUnlockTime = 10 days;

    /*//////////////////////////////////////////////////////////////
                            KATANA-SPECIFIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock vault on Katana (deployed on Katana fork)
    IERC4626 public remoteVault;

    /// @notice Mock USDC address on Katana fork
    address public katanaUsdc;

    /*//////////////////////////////////////////////////////////////
                            FORK MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Switch to Ethereum fork for test
    modifier useEthFork() {
        vm.selectFork(ethFork);
        _;
    }

    /// @notice Switch to Katana fork for test
    modifier useKatFork() {
        vm.selectFork(katFork);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Create forks - BOTH REQUIRED, no try/catch fallback
        // Tests will fail if environment variables are not set
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        string memory katRpc = vm.envString("KAT_RPC_URL");

        // Validate RPC URLs are not empty
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

        // Start with Ethereum fork for initial setup
        vm.selectFork(ethFork);

        // Set asset to USDC on Ethereum
        asset = ERC20(USDC);
        vbToken = IVaultBridgeToken(VB_USDC);
        lxlyBridge = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE);

        // Set decimals
        decimals = asset.decimals();

        // Deploy contracts on both forks
        _deployContracts();

        // Label addresses for traces
        _labelAddresses();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deployContracts() internal {
        // First deploy mock vault and remote strategy on Katana fork
        vm.selectFork(katFork);
        _deployKatanaContracts();

        // Then deploy main strategy on Ethereum fork
        vm.selectFork(ethFork);
        _deployEthereumContracts();
    }

    function _deployKatanaContracts() internal {
        // Deploy mock USDC token on Katana for testing
        katanaUsdc = address(new MockERC20("USDC", "USDC", 6));

        // Deploy mock vault on Katana
        remoteVault = IERC4626(address(new MockVault(katanaUsdc)));

        // Deploy remote strategy on Katana
        // Use placeholder for origin counterpart - will be the Ethereum strategy address
        // In production, CREATE3 would give deterministic addresses
        address originCounterpartPlaceholder = address(0xDEAD);

        remoteStrategy = new KatanaRemoteStrategy(
            katanaUsdc,
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

    function _deployEthereumContracts() internal {
        // Deploy main strategy on Ethereum with REAL VB_USDC
        // Cast to IKatanaStrategy for unified access to all functions
        strategy = IKatanaStrategy(
            address(
                new KatanaStrategy(
                    USDC,
                    "Katana USDC Strategy",
                    VB_USDC,
                    UNIFIED_BRIDGE,
                    KATANA_NETWORK_ID,
                    address(remoteStrategy),
                    depositor
                )
            )
        );

        // Get the current management (deployer) to set pending management
        address currentManagement = strategy.management();

        vm.prank(currentManagement);
        strategy.setPendingManagement(management);

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(management);
        strategy.setKeeper(keeper);

        factory = strategy.FACTORY();
    }

    function _labelAddresses() internal {
        vm.label(keeper, "keeper");
        vm.label(address(asset), "USDC");
        vm.label(management, "management");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(depositor, "depositor");
        vm.label(governance, "governance");
        vm.label(emergencyAdmin, "emergencyAdmin");
        vm.label(UNIFIED_BRIDGE, "LXLY_BRIDGE");
        vm.label(VB_USDC, "VB_USDC");
        vm.label(VB_WETH, "VB_WETH");
        vm.label(address(strategy), "KatanaStrategy");
        vm.label(address(remoteStrategy), "KatanaRemoteStrategy");
        vm.label(address(remoteVault), "MockVault");
        if (katanaUsdc != address(0)) {
            vm.label(katanaUsdc, "KatanaUSDC");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into strategy on behalf of a user
    /// @param _strategy Strategy to deposit into
    /// @param _user User making the deposit
    /// @param _amount Amount to deposit
    function depositIntoStrategy(
        IKatanaStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    /// @notice Airdrop asset and deposit into strategy
    /// @param _strategy Strategy to deposit into
    /// @param _user User making the deposit
    /// @param _amount Amount to airdrop and deposit
    function mintAndDepositIntoStrategy(
        IKatanaStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    /// @notice Airdrop tokens to an address
    /// @param _asset Token to airdrop
    /// @param _to Recipient address
    /// @param _amount Amount to airdrop
    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    /// @notice Airdrop USDC based on current fork
    /// @param _to Recipient address
    /// @param _amount Amount to airdrop
    function airdropUSDC(address _to, uint256 _amount) public {
        uint256 currentFork = vm.activeFork();

        if (currentFork == ethFork) {
            deal(USDC, _to, IERC20(USDC).balanceOf(_to) + _amount);
        } else if (currentFork == katFork) {
            deal(katanaUsdc, _to, IERC20(katanaUsdc).balanceOf(_to) + _amount);
        }
    }

    /// @notice Simulate a bridge message from Katana to Ethereum
    /// @dev Pranks as the bridge to call onMessageReceived
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
    /// @param _strategy Strategy to check
    /// @return Remote assets value
    function calculateRemoteAssets(
        IKatanaStrategy _strategy
    ) public view returns (uint256) {
        return _strategy.remoteAssets();
    }

    /// @notice Verify the VB_USDC address is correct
    /// @return True if VB_USDC address matches expected
    function verifyVbUsdcAddress() public pure returns (bool) {
        return VB_USDC == 0xBEefb9f61CC44895d8AEc381373555a64191A9c4;
    }

    /// @notice Set protocol and performance fees
    /// @param _protocolFee Protocol fee in basis points
    /// @param _performanceFee Performance fee in basis points
    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    /// @notice Get vbToken into strategy by depositing USDC
    /// @param _amount Amount of USDC to convert to vbToken
    /// @return vbShares Amount of vbToken shares received
    function getVbTokenIntoStrategy(
        uint256 _amount
    ) public returns (uint256 vbShares) {
        airdropUSDC(address(this), _amount);
        IERC20(USDC).approve(VB_USDC, _amount);
        vbShares = vbToken.deposit(_amount, address(strategy));
    }

    /// @notice Check strategy totals match expected values
    /// @param _totalAssets Expected total assets
    /// @param _remoteAssets Expected remote assets
    /// @param _localBalance Expected local balance
    function checkStrategyTotals(
        uint256 _totalAssets,
        uint256 _remoteAssets,
        uint256 _localBalance
    ) public {
        assertEq(strategy.totalAssets(), _totalAssets, "Total assets mismatch");
        assertEq(
            strategy.remoteAssets(),
            _remoteAssets,
            "Remote assets mismatch"
        );
        assertEq(
            IERC20(USDC).balanceOf(address(strategy)),
            _localBalance,
            "Local balance mismatch"
        );
    }
}

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

/// @title MockERC20
/// @notice Simple mock ERC20 token for testing on Katana fork
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @title MockVault
/// @notice Simple mock ERC4626 vault for testing on Katana fork
/// @dev Implements minimal ERC4626 interface for testing
contract MockVault is IERC4626 {
    ERC20 public immutable _asset;
    mapping(address => uint256) public shares;
    uint256 public totalShares;
    uint256 public totalAssetAmount;

    // Profit/loss simulation
    int256 public profitLossAdjustment;

    constructor(address asset_) {
        _asset = ERC20(asset_);
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT/LOSS SIMULATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Add profit to the vault (for testing)
    /// @param amount Amount of profit to add
    function addProfit(uint256 amount) external {
        totalAssetAmount += amount;
    }

    /// @notice Simulate loss in the vault (for testing)
    /// @param amount Amount of loss to simulate
    function simulateLoss(uint256 amount) external {
        if (amount > totalAssetAmount) {
            totalAssetAmount = 0;
        } else {
            totalAssetAmount -= amount;
        }
    }

    /// @notice Set exact total assets (for testing)
    /// @param amount New total assets value
    function setTotalAssets(uint256 amount) external {
        totalAssetAmount = amount;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

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
        require(shares[owner] >= _shares, "MockVault: insufficient shares");

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
        require(shares[owner] >= _shares, "MockVault: insufficient shares");

        assets = convertToAssets(_shares);
        shares[owner] -= _shares;
        totalShares -= _shares;
        totalAssetAmount -= assets;
        _asset.transfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return shares[account];
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(shares[msg.sender] >= amount, "MockVault: insufficient shares");
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
        require(shares[from] >= amount, "MockVault: insufficient shares");
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

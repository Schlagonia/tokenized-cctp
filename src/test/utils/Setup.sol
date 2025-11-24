// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {CCTPStrategy as Strategy, ERC20} from "../../CCTPStrategy.sol";
import {CCTPRemoteStrategy as RemoteStrategy} from "../../CCTPRemoteStrategy.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {RemoteStrategyFactory} from "../../RemoteStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

// CCTP interfaces
import {ITokenMessenger} from "../../interfaces/circle/ITokenMessenger.sol";
import {IMessageTransmitter} from "../../interfaces/circle/IMessageTransmitter.sol";

import {ICreateX} from "../../interfaces/ICreateX.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is Test, IEvents {
    ICreateX public createX =
        ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;
    RemoteStrategy public remoteStrategy;

    StrategyFactory public strategyFactory;
    RemoteStrategyFactory public remoteStrategyFactory;
    RemoteStrategyFactory public baseRemoteStrategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);
    address public depositor = address(6);
    address public governance = address(7);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1_000_000e6;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // USDC contracts on both chains
    IERC20 public constant USDC_ETHEREUM =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant USDC_BASE =
        IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    // CCTP contracts
    ITokenMessenger public constant ETH_TOKEN_MESSENGER =
        ITokenMessenger(0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d);
    IMessageTransmitter public constant ETH_MESSAGE_TRANSMITTER =
        IMessageTransmitter(0x81D40F21F12A8F0E3252Bccb954D722d4c464B64);
    ITokenMessenger public constant BASE_TOKEN_MESSENGER =
        ITokenMessenger(0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d);
    IMessageTransmitter public constant BASE_MESSAGE_TRANSMITTER =
        IMessageTransmitter(0x81D40F21F12A8F0E3252Bccb954D722d4c464B64);

    // Fork IDs
    uint256 public ethFork;
    uint256 public baseFork;

    // USDC whales for funding tests
    address public constant ETH_USDC_WHALE =
        0xaD354CfBAa4A8572DD6Df021514a3931A8329Ef5;
    address public constant BASE_USDC_WHALE =
        0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;

    // Domain IDs
    uint32 public constant ETHEREUM_DOMAIN = 0;
    uint32 public constant BASE_DOMAIN = 6;

    // Vault on Base
    IERC4626 public vault;

    // Fork modifiers
    modifier useEthFork() {
        vm.selectFork(ethFork);
        _;
    }

    modifier useBaseFork() {
        vm.selectFork(baseFork);
        _;
    }

    function setUp() public virtual {
        _setTokenAddrs();

        // Create forks first
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        string memory baseRpc = vm.envString("BASE_RPC_URL");

        ethFork = vm.createFork(ethRpc);
        baseFork = vm.createFork(baseRpc);

        // Start with Ethereum fork
        vm.selectFork(ethFork);

        // Set asset to USDC (for CCTP strategies) - after fork is active
        asset = ERC20(tokenAddrs["USDC"]);

        // Set decimals
        decimals = asset.decimals();

        // Set the vault address early
        vault = IERC4626(0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca);

        // Now deploy main strategy with the actual remote address
        (strategyFactory, strategy) = deployMainnetContracts();

        (remoteStrategyFactory, remoteStrategy) = deployRemoteContracts();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(depositor, "depositor");
        vm.label(governance, "governance");
        vm.label(emergencyAdmin, "emergencyAdmin");
        vm.label(address(USDC_ETHEREUM), "USDC_ETHEREUM");
        vm.label(address(USDC_BASE), "USDC_BASE");
        vm.label(address(ETH_TOKEN_MESSENGER), "ETH_TOKEN_MESSENGER");
        vm.label(address(ETH_MESSAGE_TRANSMITTER), "ETH_MESSAGE_TRANSMITTER");
        vm.label(address(BASE_TOKEN_MESSENGER), "TOKEN_MESSENGER");
        vm.label(address(BASE_MESSAGE_TRANSMITTER), "MESSAGE_TRANSMITTER");
    }

    function deployMainnetContracts()
        public
        returns (StrategyFactory _strategyFactory, IStrategyInterface _strategy)
    {
        // Deploy Strategy on Ethereum
        vm.selectFork(ethFork);

        bytes memory creationCode = abi.encodePacked(
            type(RemoteStrategyFactory).creationCode,
            abi.encode(
                management,
                USDC_ETHEREUM,
                ETH_TOKEN_MESSENGER,
                ETH_MESSAGE_TRANSMITTER
            )
        );
        bytes32 salt = bytes32(abi.encodePacked("gigga goa poo poo"));

        address _remoteFactory = ICreateX(createX).deployCreate3(
            salt,
            creationCode
        );

        _strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin,
            address(USDC_ETHEREUM),
            address(ETH_TOKEN_MESSENGER),
            address(ETH_MESSAGE_TRANSMITTER),
            address(_remoteFactory)
        );

        // Deploy strategy directly with the known remote counterpart
        _strategy = IStrategyInterface(
            _strategyFactory.newStrategy(
                "CCTP USDC Strategy",
                BASE_DOMAIN,
                address(vault),
                depositor
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        factory = _strategy.FACTORY();
    }

    function deployRemoteContracts()
        public
        returns (
            RemoteStrategyFactory _remoteFactory,
            RemoteStrategy _remoteStrategy
        )
    {
        // Deploy on Base
        vm.selectFork(baseFork);

        bytes memory creationCode = abi.encodePacked(
            type(RemoteStrategyFactory).creationCode,
            abi.encode(
                governance,
                USDC_BASE,
                BASE_TOKEN_MESSENGER,
                BASE_MESSAGE_TRANSMITTER
            )
        );
        bytes32 salt = bytes32(abi.encodePacked("gigga goa poo poo"));

        _remoteFactory = RemoteStrategyFactory(
            ICreateX(createX).deployCreate3(salt, creationCode)
        );

        _remoteStrategy = RemoteStrategy(
            _remoteFactory.deployRemoteStrategy(
                address(vault),
                ETHEREUM_DOMAIN,
                address(strategy)
            )
        );

        vm.prank(governance);
        _remoteStrategy.setKeeper(keeper, true);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function airdropUSDC(address _to, uint256 _amount) public {
        uint256 currentFork = vm.activeFork();

        if (currentFork == ethFork) {
            deal(
                address(USDC_ETHEREUM),
                _to,
                USDC_ETHEREUM.balanceOf(_to) + _amount
            );
        } else if (currentFork == baseFork) {
            deal(address(USDC_BASE), _to, USDC_BASE.balanceOf(_to) + _amount);
        }
    }

    function simulateCCTPMessage(
        uint32 sourceDomain,
        bytes32 sender,
        uint32 destinationDomain,
        bytes32 recipient,
        bytes memory messageBody
    ) public {
        // Simulate message relay between chains
        if (destinationDomain == BASE_DOMAIN) {
            vm.selectFork(baseFork);
            // Prank as message transmitter to deliver the message
            vm.prank(address(BASE_MESSAGE_TRANSMITTER));
            remoteStrategy.handleReceiveFinalizedMessage(
                sourceDomain,
                sender,
                2000, // FINALITY_THRESHOLD_FINALIZED
                messageBody
            );
        } else if (destinationDomain == ETHEREUM_DOMAIN) {
            vm.selectFork(ethFork);
            vm.prank(address(ETH_MESSAGE_TRANSMITTER));
            strategy.handleReceiveFinalizedMessage(
                sourceDomain,
                sender,
                2000, // FINALITY_THRESHOLD_FINALIZED
                messageBody
            );
        }
    }

    function calculateRemoteAssets(
        IStrategyInterface _strategy
    ) public view returns (uint256) {
        // In the new accounting model, remote assets = totalAssets - local balance
        uint256 totalAssets = _strategy.totalAssets();
        uint256 localBalance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        if (totalAssets > localBalance) {
            return totalAssets - localBalance;
        }
        return 0;
    }

    function checkCrossChainInvariant() public {
        // Total assets should equal sum of local and remote
        vm.selectFork(ethFork);
        uint256 totalAssets = strategy.totalAssets();
        uint256 localBalance = USDC_ETHEREUM.balanceOf(address(strategy));
        uint256 remoteAssets = calculateRemoteAssets(strategy);

        assertApproxEqAbs(
            totalAssets,
            localBalance + remoteAssets,
            10, // Allow small rounding difference
            "Total assets invariant broken"
        );
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }
}

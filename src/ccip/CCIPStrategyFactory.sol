// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CCIPStrategy as Strategy} from "./CCIPStrategy.sol";
import {ICCIPStrategy} from "../interfaces/ICCIPStrategy.sol";
import {CREATE} from "../libraries/CREATE.sol";

interface ICCIPRemoteFactory {
    function computeCreateAddress(
        address _vault,
        uint64 _originChainSelector,
        address _originCounterpart
    ) external view returns (address);
}

/// @title CCIPStrategyFactory
/// @notice Generic factory for CCIP origin strategies for any CCIP-enabled
///         token. Mirrors OFTStrategyFactory: it precomputes the origin
///         address (CREATE nonce) and the remote counterpart (CREATE3 via the
///         remote factory), so the pair knows each other before deploy. Token
///         / router are supplied per deployment.
contract CCIPStrategyFactory {
    event NewStrategy(
        address indexed strategy,
        uint64 indexed remoteChainSelector
    );

    event GasLimitSet(uint256 gasLimit);

    /// @notice Roles applied to deployed origin strategies.
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice The remote factory (same address on all chains via CreateX).
    address public immutable REMOTE_FACTORY;

    /// @notice Gas limit for the destination ccipReceive execution.
    uint256 public gasLimit;

    uint256 public nonce;

    /// @notice remoteChainSelector => remoteCounterpart => strategy.
    mapping(uint64 => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _remoteFactory,
        uint256 _gasLimit
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        REMOTE_FACTORY = _remoteFactory;
        gasLimit = _gasLimit;
        nonce = 1;
    }

    /// @notice Deploy a new origin strategy linked to its remote counterpart.
    /// @param _name Strategy name
    /// @param _asset CCIP token on the origin chain
    /// @param _router CCIP router on the origin chain
    /// @param _originChainSelector CCIP chain selector of this (origin) chain
    /// @param _remoteChainSelector CCIP chain selector of the remote chain
    /// @param _remoteChainId Chain id of the remote chain
    /// @param _remoteVault ERC4626 vault the remote deploys into
    function newStrategy(
        string memory _name,
        address _asset,
        address _router,
        uint64 _originChainSelector,
        uint64 _remoteChainSelector,
        uint256 _remoteChainId,
        address _remoteVault
    ) external returns (address) {
        address predicted = computeCreateAddress(nonce);
        address remoteCounterpart = computeRemoteCreateAddress(
            _remoteVault,
            _originChainSelector,
            predicted
        );

        address strategy = address(
            new Strategy(
                _asset,
                _name,
                _router,
                _remoteChainSelector,
                _remoteChainId,
                remoteCounterpart,
                gasLimit
            )
        );
        require(strategy == predicted, "!predicted");

        _setupRoles(strategy);

        deployments[_remoteChainSelector][remoteCounterpart] = strategy;
        nonce++;

        emit NewStrategy(strategy, _remoteChainSelector);
        return strategy;
    }

    function _setupRoles(address _strategy) internal {
        ICCIPStrategy s = ICCIPStrategy(_strategy);
        s.setPerformanceFee(0);
        s.setProfitMaxUnlockTime(0);
        s.setPerformanceFeeRecipient(performanceFeeRecipient);
        s.setKeeper(keeper);
        s.setEmergencyAdmin(emergencyAdmin);
        s.setPendingManagement(management);
    }

    /// @notice Predict the origin address for a given factory nonce.
    function computeCreateAddress(
        uint256 _nonce
    ) public view returns (address) {
        return CREATE.predict(address(this), _nonce);
    }

    /// @notice Compute the remote counterpart address for an origin.
    function computeRemoteCreateAddress(
        address _vault,
        uint64 _originChainSelector,
        address _originCounterpart
    ) public view returns (address) {
        return
            ICCIPRemoteFactory(REMOTE_FACTORY).computeCreateAddress(
                _vault,
                _originChainSelector,
                _originCounterpart
            );
    }

    function setGasLimit(uint256 _gasLimit) external {
        require(msg.sender == management, "!management");
        gasLimit = _gasLimit;
        emit GasLimitSet(_gasLimit);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }
}

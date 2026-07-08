// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {OFTStrategy as Strategy} from "./OFTStrategy.sol";
import {IOFTStrategy} from "../interfaces/IOFTStrategy.sol";
import {CREATE} from "../libraries/CREATE.sol";

interface IOFTRemoteFactory {
    function computeCreateAddress(
        address _vault,
        uint32 _originEid,
        address _originCounterpart
    ) external view returns (address);
}

/// @title OFTStrategyFactory
/// @notice Generic factory for OFT origin strategies for any OFT token. Mirrors
///         StrategyFactory: it precomputes the origin address (CREATE nonce)
///         and the remote counterpart (CREATE3 via the remote factory), so the
///         pair knows each other before either is deployed. The token / OFT
///         adapter / endpoint are supplied per deployment rather than hardcoded.
contract OFTStrategyFactory {
    event NewStrategy(address indexed strategy, uint32 indexed remoteEid);

    /// @notice Roles applied to deployed origin strategies.
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice The remote factory (same address on all chains via CreateX).
    address public immutable REMOTE_FACTORY;

    uint256 public nonce;

    /// @notice remoteEid => remoteCounterpart => strategy.
    mapping(uint32 => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _remoteFactory
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        REMOTE_FACTORY = _remoteFactory;
        nonce = 1;
    }

    /// @notice Deploy a new origin strategy linked to its remote counterpart.
    /// @param _name Strategy name
    /// @param _asset OFT token on the origin chain
    /// @param _oft OFT adapter on the origin chain
    /// @param _endpoint LayerZero endpoint on the origin chain
    /// @param _originEid LayerZero endpoint ID of this (origin) chain
    /// @param _remoteEid LayerZero endpoint ID of the remote chain
    /// @param _remoteChainId Chain id of the remote chain
    /// @param _remoteVault ERC4626 vault the remote deploys into
    function newStrategy(
        string memory _name,
        address _asset,
        address _oft,
        address _endpoint,
        uint32 _originEid,
        uint32 _remoteEid,
        uint256 _remoteChainId,
        address _remoteVault
    ) external returns (address) {
        address predicted = computeCreateAddress(nonce);
        address remoteCounterpart = computeRemoteCreateAddress(
            _remoteVault,
            _originEid,
            predicted
        );

        address strategy = address(
            new Strategy(
                _asset,
                _name,
                _oft,
                _endpoint,
                _remoteEid,
                _remoteChainId,
                remoteCounterpart,
                "" // origin token sends ride the OFT's enforced options
            )
        );
        require(strategy == predicted, "!predicted");

        _setupRoles(strategy);

        deployments[_remoteEid][remoteCounterpart] = strategy;
        nonce++;

        emit NewStrategy(strategy, _remoteEid);
        return strategy;
    }

    function _setupRoles(address _strategy) internal {
        IOFTStrategy s = IOFTStrategy(_strategy);
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
        uint32 _originEid,
        address _originCounterpart
    ) public view returns (address) {
        return
            IOFTRemoteFactory(REMOTE_FACTORY).computeCreateAddress(
                _vault,
                _originEid,
                _originCounterpart
            );
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

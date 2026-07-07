// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {OFTStrategy as Strategy} from "./OFTStrategy.sol";
import {CREATE} from "./libraries/CREATE.sol";

interface IOFTRemoteFactory {
    function computeCreateAddress(
        address _vault,
        uint32 _originEid,
        address _originCounterpart
    ) external view returns (address);
}

interface IOriginSetup {
    function setPerformanceFee(uint16) external;

    function setProfitMaxUnlockTime(uint256) external;

    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setEmergencyAdmin(address) external;

    function setPendingManagement(address) external;
}

/// @title OFTStrategyFactory
/// @notice Factory for OFT origin strategies. Mirrors StrategyFactory: it
///         precomputes the origin address (CREATE nonce) and the remote
///         counterpart (CREATE3 via the remote factory), so the pair knows
///         each other before either is deployed.
/// @dev The origin's source-chain OFT config (asset, adapter, endpoint) is
///      fixed; token transfers ride the OFT's enforced options so no extra
///      options are attached to the origin.
contract OFTStrategyFactory {
    event NewStrategy(address indexed strategy, uint32 indexed remoteEid);

    /// @notice Roles applied to deployed origin strategies.
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice The remote factory (same address on all chains via CreateX).
    address public immutable REMOTE_FACTORY;

    /// @notice Source-chain OFT config.
    address public immutable ASSET;
    address public immutable OFT;
    address public immutable ENDPOINT;

    /// @notice LayerZero endpoint ID of this (origin) chain.
    uint32 public immutable ORIGIN_EID;

    uint256 public nonce;

    /// @notice remoteEid => remoteCounterpart => strategy.
    mapping(uint32 => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _remoteFactory,
        address _asset,
        address _oft,
        address _endpoint,
        uint32 _originEid
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        REMOTE_FACTORY = _remoteFactory;
        ASSET = _asset;
        OFT = _oft;
        ENDPOINT = _endpoint;
        ORIGIN_EID = _originEid;
        nonce = 1;
    }

    /// @notice Deploy a new origin strategy, linked to its remote counterpart.
    /// @param _name Strategy name
    /// @param _remoteEid LayerZero endpoint ID of the remote chain
    /// @param _remoteChainId Chain id of the remote chain
    /// @param _remoteVault The ERC4626 vault the remote deploys into
    /// @param _depositer Address allowed to deposit
    function newStrategy(
        string calldata _name,
        uint32 _remoteEid,
        uint256 _remoteChainId,
        address _remoteVault,
        address _depositer
    ) external returns (address) {
        address predicted = computeCreateAddress(nonce);
        address remoteCounterpart = computeRemoteCreateAddress(
            _remoteVault,
            predicted
        );

        Strategy strategy = new Strategy(
            ASSET,
            _name,
            OFT,
            ENDPOINT,
            _remoteEid,
            _remoteChainId,
            remoteCounterpart,
            _depositer,
            "" // origin token sends ride the OFT's enforced options
        );
        require(address(strategy) == predicted, "!predicted");

        IOriginSetup s = IOriginSetup(address(strategy));
        s.setPerformanceFee(0);
        s.setProfitMaxUnlockTime(0);
        s.setPerformanceFeeRecipient(performanceFeeRecipient);
        s.setKeeper(keeper);
        s.setEmergencyAdmin(emergencyAdmin);
        s.setPendingManagement(management);

        deployments[_remoteEid][remoteCounterpart] = address(strategy);
        nonce++;

        emit NewStrategy(address(strategy), _remoteEid);
        return address(strategy);
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
        address _originCounterpart
    ) public view returns (address) {
        return
            IOFTRemoteFactory(REMOTE_FACTORY).computeCreateAddress(
                _vault,
                ORIGIN_EID,
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

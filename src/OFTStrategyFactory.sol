// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {OFTStrategy} from "./OFTStrategy.sol";
import {OFTRemoteStrategy} from "./OFTRemoteStrategy.sol";
import {OFTOptions} from "./libraries/OFTOptions.sol";

interface IOriginSetup {
    function setPerformanceFee(uint16) external;

    function setProfitMaxUnlockTime(uint256) external;

    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setEmergencyAdmin(address) external;

    function setPendingManagement(address) external;
}

/// @title OFTStrategyFactory
/// @notice Deploys the OFT strategy pair. Deploy this factory on each chain
///         and call the matching method: `newOrigin` on the source chain,
///         `newRemote` on the destination chain.
/// @dev The factory computes the LayerZero executor options and passes them
///      into the strategy constructor, so no options are ever hand-encoded or
///      set post-deploy. The origin's token transfers ride the OFT's enforced
///      options (empty extra options); the remote attaches compose reports and
///      so is given lzReceive + lzCompose options.
contract OFTStrategyFactory {
    event NewOrigin(address indexed strategy, uint32 indexed remoteEid);

    event NewRemote(address indexed strategy, uint32 indexed originEid);

    event GasSet(uint128 lzReceiveGas, uint128 lzComposeGas);

    /// @notice Yearn roles applied to origin (TokenizedStrategy) deployments.
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice Executor gas for the destination lzReceive (token credit).
    uint128 public lzReceiveGas;

    /// @notice Executor gas for the destination lzCompose (report handler).
    uint128 public lzComposeGas;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;

        // Sensible defaults; the report handler is a small decode + SSTOREs.
        lzReceiveGas = 80_000;
        lzComposeGas = 100_000;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the origin strategy on the source chain.
    /// @dev Token transfers ride the OFT's enforced options, so no extra
    ///      options are attached (empty).
    function newOrigin(
        address _asset,
        string calldata _name,
        address _oft,
        address _endpoint,
        uint32 _remoteEid,
        uint256 _remoteChainId,
        address _remoteCounterpart,
        address _depositer
    ) external returns (address) {
        OFTStrategy strategy = new OFTStrategy(
            _asset,
            _name,
            _oft,
            _endpoint,
            _remoteEid,
            _remoteChainId,
            _remoteCounterpart,
            _depositer,
            "" // origin sends tokens only; rides the OFT's enforced options
        );

        IOriginSetup s = IOriginSetup(address(strategy));
        s.setPerformanceFee(0);
        s.setProfitMaxUnlockTime(0);
        s.setPerformanceFeeRecipient(performanceFeeRecipient);
        s.setKeeper(keeper);
        s.setEmergencyAdmin(emergencyAdmin);
        s.setPendingManagement(management);

        emit NewOrigin(address(strategy), _remoteEid);
        return address(strategy);
    }

    /// @notice Deploy the remote strategy on the destination chain.
    /// @dev Attaches compose reports, so it is given the computed lzReceive +
    ///      lzCompose options. Its keeper is set by governance post-deploy.
    function newRemote(
        address _asset,
        address _governance,
        address _oft,
        address _endpoint,
        uint32 _originEid,
        address _originCounterpart,
        address _vault
    ) external returns (address) {
        OFTRemoteStrategy strategy = new OFTRemoteStrategy(
            _asset,
            _governance,
            _oft,
            _endpoint,
            _originEid,
            _originCounterpart,
            _vault,
            remoteOptions()
        );

        emit NewRemote(address(strategy), _originEid);
        return address(strategy);
    }

    /*//////////////////////////////////////////////////////////////
                            CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice The compose options the factory attaches to remote strategies.
    function remoteOptions() public view returns (bytes memory) {
        return OFTOptions.composeOptions(lzReceiveGas, lzComposeGas);
    }

    /// @notice Tune the executor gas used for future deployments.
    function setGas(uint128 _lzReceiveGas, uint128 _lzComposeGas) external {
        require(msg.sender == management, "!management");
        lzReceiveGas = _lzReceiveGas;
        lzComposeGas = _lzComposeGas;
        emit GasSet(_lzReceiveGas, _lzComposeGas);
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

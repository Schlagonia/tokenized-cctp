// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CCTPRemoteStrategy as RemoteStrategy} from "./CCTPRemoteStrategy.sol";
import {CREATE3} from "./libraries/CREATE3.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {BaseCCTP} from "./bases/BaseCCTP.sol";

/**
 * @title RemoteStrategyFactory
 * @notice Factory for deterministic deployment of remote strategies across chains
 * @dev Deployed at the same address on all chains using CREATE2
 */
contract RemoteStrategyFactory is Governance, BaseCCTP {
    event NewRemoteStrategy(
        address indexed strategy,
        address indexed vault,
        uint32 indexed remoteDomain,
        address remoteCounterpart
    );

    /// @notice Track deployments: keccak256(vault, remoteDomain, remoteCounterpart) => strategy
    mapping(bytes32 => address) public deployments;

    constructor(
        address _governance,
        address _usdc,
        address _tokenMessenger,
        address _messageTransmitter
    )
        Governance(_governance)
        BaseCCTP(_usdc, _tokenMessenger, _messageTransmitter)
    {}

    /**
     * @notice Deploy a new remote strategy deterministically
     * @param _vault The ERC4626 vault to deposit into
     * @param _remoteDomain The domain ID of the origin chain
     * @param _remoteCounterpart The origin strategy address
     * @return The address of the deployed remote strategy
     */
    function deployRemoteStrategy(
        address _vault,
        uint32 _remoteDomain,
        address _remoteCounterpart
    ) external returns (address) {
        // Create deterministic salt from parameters (not msg.sender)
        bytes32 salt = getSalt(_vault, _remoteDomain, _remoteCounterpart);

        // Check if already deployed
        if (deployments[salt] != address(0)) {
            return deployments[salt];
        }

        // Deploy with CREATE3
        bytes memory creationCode = abi.encodePacked(
            type(RemoteStrategy).creationCode,
            abi.encode(
                USDC,
                governance,
                address(TOKEN_MESSENGER),
                address(MESSAGE_TRANSMITTER),
                _remoteDomain,
                _remoteCounterpart,
                _vault
            )
        );

        address strategyAddress = CREATE3.deploy(salt, creationCode, 0);

        deployments[salt] = strategyAddress;

        emit NewRemoteStrategy(
            strategyAddress,
            _vault,
            _remoteDomain,
            _remoteCounterpart
        );

        return strategyAddress;
    }

    /**
     * @notice Compute the deterministic address for a remote strategy
     * @param _vault The ERC4626 vault to deposit into
     * @param _remoteDomain The domain ID of the origin chain
     * @param _remoteCounterpart The origin strategy address
     * @return The deterministic address where the strategy will be deployed
     */
    function computeCreateAddress(
        address _vault,
        //address _governance,
        uint32 _remoteDomain,
        address _remoteCounterpart
    ) public view returns (address) {
        bytes32 salt = getSalt(_vault, _remoteDomain, _remoteCounterpart);

        // Compute CREATE2 address
        return CREATE3.getDeployed(address(this), salt);
    }

    function getSalt(
        address _vault,
        uint32 _remoteDomain,
        address _remoteCounterpart
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_vault, _remoteDomain, _remoteCounterpart));
    }

    function handleReceiveFinalizedMessage(
        uint32 _sourceDomain,
        bytes32 _sender,
        uint32 _finalityThresholdExecuted,
        bytes calldata _messageBody
    ) external virtual override returns (bool) {
        revert("Not implemented");
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {OFTRemoteStrategy as RemoteStrategy} from "./OFTRemoteStrategy.sol";
import {CREATE3} from "../libraries/CREATE3.sol";
import {OFTOptions} from "../libraries/OFTOptions.sol";
import {Governance} from "@periphery/utils/Governance.sol";

/// @title OFTRemoteStrategyFactory
/// @notice Generic factory for deterministic deployment of OFT remote
///         strategies for any OFT token. Deploy at the same address on all
///         chains (via CreateX) so the origin factory can precompute the
///         remote counterpart. Mirrors RemoteStrategyFactory, but the token /
///         OFT adapter / endpoint are supplied per deployment rather than
///         hardcoded. The factory computes and sets the LayerZero compose
///         options.
contract OFTRemoteStrategyFactory is Governance {
    event NewRemoteStrategy(
        address indexed strategy,
        address indexed vault,
        uint32 indexed originEid,
        address originCounterpart
    );

    event GasSet(uint128 lzReceiveGas, uint128 lzComposeGas);

    /// @notice Executor gas for the destination lzReceive / lzCompose.
    uint128 public lzReceiveGas;
    uint128 public lzComposeGas;

    /// @notice keccak256(vault, originEid, originCounterpart) => strategy.
    mapping(bytes32 => address) public deployments;

    constructor(
        address _governance,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) Governance(_governance) {
        lzReceiveGas = _lzReceiveGas;
        lzComposeGas = _lzComposeGas;
    }

    /// @notice Deploy a remote strategy deterministically.
    /// @param _asset The OFT token on this chain (the vault's asset)
    /// @param _oft The OFT adapter that bridges the asset
    /// @param _endpoint The LayerZero endpoint on this chain
    /// @param _vault The ERC4626 vault to deposit into
    /// @param _originEid LayerZero endpoint ID of the origin chain
    /// @param _originCounterpart The origin strategy address
    function deployRemoteStrategy(
        address _asset,
        address _oft,
        address _endpoint,
        address _vault,
        uint32 _originEid,
        address _originCounterpart
    ) external returns (address) {
        bytes32 salt = getSalt(_vault, _originEid, _originCounterpart);
        if (deployments[salt] != address(0)) {
            return deployments[salt];
        }

        bytes memory creationCode = abi.encodePacked(
            type(RemoteStrategy).creationCode,
            abi.encode(
                _asset,
                governance,
                _oft,
                _endpoint,
                _originEid,
                _originCounterpart,
                _vault,
                remoteOptions()
            )
        );

        address strategy = CREATE3.deploy(salt, creationCode, 0);
        deployments[salt] = strategy;

        emit NewRemoteStrategy(
            strategy,
            _vault,
            _originEid,
            _originCounterpart
        );
        return strategy;
    }

    /// @notice Compute the deterministic address of a remote strategy.
    /// @dev Independent of the token/OFT config, so the origin factory can
    ///      predict it knowing only the vault, origin EID and origin address.
    function computeCreateAddress(
        address _vault,
        uint32 _originEid,
        address _originCounterpart
    ) public view returns (address) {
        return
            CREATE3.getDeployed(
                address(this),
                getSalt(_vault, _originEid, _originCounterpart)
            );
    }

    function getSalt(
        address _vault,
        uint32 _originEid,
        address _originCounterpart
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_vault, _originEid, _originCounterpart));
    }

    /// @notice The compose options the factory sets on remote strategies.
    function remoteOptions() public view returns (bytes memory) {
        return OFTOptions.composeOptions(lzReceiveGas, lzComposeGas);
    }

    function setGas(
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external onlyGovernance {
        lzReceiveGas = _lzReceiveGas;
        lzComposeGas = _lzComposeGas;
        emit GasSet(_lzReceiveGas, _lzComposeGas);
    }
}

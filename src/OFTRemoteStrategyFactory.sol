// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {OFTRemoteStrategy as RemoteStrategy} from "./OFTRemoteStrategy.sol";
import {CREATE3} from "./libraries/CREATE3.sol";
import {OFTOptions} from "./libraries/OFTOptions.sol";
import {Governance} from "@periphery/utils/Governance.sol";

/// @title OFTRemoteStrategyFactory
/// @notice Factory for deterministic deployment of OFT remote strategies.
/// @dev Deployed at the same address on all chains (via CreateX) so the origin
///      factory can precompute the remote counterpart. Mirrors
///      RemoteStrategyFactory. The destination-chain OFT config (asset, OFT
///      adapter, endpoint) is fixed per chain; the factory computes and sets
///      the LayerZero compose options.
contract OFTRemoteStrategyFactory is Governance {
    event NewRemoteStrategy(
        address indexed strategy,
        address indexed vault,
        uint32 indexed originEid,
        address originCounterpart
    );

    event GasSet(uint128 lzReceiveGas, uint128 lzComposeGas);

    /// @notice The asset (OFT token) on this chain.
    address public immutable ASSET;

    /// @notice The OFT adapter that bridges the asset.
    address public immutable OFT;

    /// @notice The LayerZero endpoint on this chain.
    address public immutable ENDPOINT;

    /// @notice Executor gas for the destination lzReceive / lzCompose.
    uint128 public lzReceiveGas;
    uint128 public lzComposeGas;

    /// @notice keccak256(vault, originEid, originCounterpart) => strategy.
    mapping(bytes32 => address) public deployments;

    constructor(
        address _governance,
        address _asset,
        address _oft,
        address _endpoint,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) Governance(_governance) {
        ASSET = _asset;
        OFT = _oft;
        ENDPOINT = _endpoint;
        lzReceiveGas = _lzReceiveGas;
        lzComposeGas = _lzComposeGas;
    }

    /// @notice Deploy a remote strategy deterministically.
    /// @param _vault The ERC4626 vault to deposit into
    /// @param _originEid LayerZero endpoint ID of the origin chain
    /// @param _originCounterpart The origin strategy address
    function deployRemoteStrategy(
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
                ASSET,
                governance,
                OFT,
                ENDPOINT,
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

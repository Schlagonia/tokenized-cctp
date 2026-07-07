// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CCIPRemoteStrategy as RemoteStrategy} from "./CCIPRemoteStrategy.sol";
import {CREATE3} from "../libraries/CREATE3.sol";
import {Governance} from "@periphery/utils/Governance.sol";

/// @title CCIPRemoteStrategyFactory
/// @notice Generic factory for deterministic deployment of CCIP remote
///         strategies for any CCIP-enabled token. Deploy at the same address
///         on all chains (via CreateX) so the origin factory can precompute
///         the remote counterpart. Mirrors OFTRemoteStrategyFactory; the token
///         / router / vault are supplied per deployment. Sets the destination
///         ccipReceive gas limit.
contract CCIPRemoteStrategyFactory is Governance {
    event NewRemoteStrategy(
        address indexed strategy,
        address indexed vault,
        uint64 indexed originChainSelector,
        address originCounterpart
    );

    event GasLimitSet(uint256 gasLimit);

    /// @notice Gas limit for the destination ccipReceive execution.
    uint256 public gasLimit;

    /// @notice keccak256(vault, originChainSelector, originCounterpart) => strategy.
    mapping(bytes32 => address) public deployments;

    constructor(
        address _governance,
        uint256 _gasLimit
    ) Governance(_governance) {
        gasLimit = _gasLimit;
    }

    /// @notice Deploy a remote strategy deterministically.
    /// @param _asset The CCIP token on this chain (the vault's asset)
    /// @param _router The CCIP router on this chain
    /// @param _vault The ERC4626 vault to deposit into
    /// @param _originChainSelector CCIP chain selector of the origin chain
    /// @param _originCounterpart The origin strategy address
    function deployRemoteStrategy(
        address _asset,
        address _router,
        address _vault,
        uint64 _originChainSelector,
        address _originCounterpart
    ) external returns (address) {
        bytes32 salt = getSalt(
            _vault,
            _originChainSelector,
            _originCounterpart
        );
        if (deployments[salt] != address(0)) {
            return deployments[salt];
        }

        bytes memory creationCode = abi.encodePacked(
            type(RemoteStrategy).creationCode,
            abi.encode(
                _asset,
                governance,
                _router,
                _originChainSelector,
                _originCounterpart,
                _vault,
                gasLimit
            )
        );

        address strategy = CREATE3.deploy(salt, creationCode, 0);
        deployments[salt] = strategy;

        emit NewRemoteStrategy(
            strategy,
            _vault,
            _originChainSelector,
            _originCounterpart
        );
        return strategy;
    }

    /// @notice Compute the deterministic address of a remote strategy.
    function computeCreateAddress(
        address _vault,
        uint64 _originChainSelector,
        address _originCounterpart
    ) public view returns (address) {
        return
            CREATE3.getDeployed(
                address(this),
                getSalt(_vault, _originChainSelector, _originCounterpart)
            );
    }

    function getSalt(
        address _vault,
        uint64 _originChainSelector,
        address _originCounterpart
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(_vault, _originChainSelector, _originCounterpart)
            );
    }

    function setGasLimit(uint256 _gasLimit) external onlyGovernance {
        gasLimit = _gasLimit;
        emit GasLimitSet(_gasLimit);
    }
}

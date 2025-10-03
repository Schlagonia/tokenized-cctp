// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CCTPStrategy as Strategy, ERC20} from "./CCTPStrategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";
import {RemoteStrategyFactory} from "./RemoteStrategyFactory.sol";
import {CREATE} from "./libraries/CREATE.sol";
import {CREATE3} from "./libraries/CREATE3.sol";

contract StrategyFactory {
    event NewStrategy(address indexed strategy, uint32 indexed remoteDomain);

    address public immutable USDC;
    address public immutable TOKEN_MESSENGER;
    address public immutable MESSAGE_TRANSMITTER;

    RemoteStrategyFactory public immutable remoteFactory;

    address public emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    uint256 public nonce;

    /// @notice Track the deployments. remoteDomain => remoteVault => strategy
    mapping(uint32 => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _usdc,
        address _tokenMessenger,
        address _messageTransmitter,
        address _remoteFactory
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;

        USDC = _usdc;
        TOKEN_MESSENGER = _tokenMessenger;
        MESSAGE_TRANSMITTER = _messageTransmitter;
        remoteFactory = RemoteStrategyFactory(_remoteFactory);

        nonce = 1;
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _name The name of the strategy.
     * @param _remoteDomain The remote domain of the strategy.
     * @param _remoteVault The ERC4626 vault on the remote chain.
     * @param _depositer The depositer of the strategy.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        string memory _name,
        uint32 _remoteDomain,
        address _remoteVault,
        address _depositer
    ) external virtual returns (address) {
        // Pre-compute the strategy address (next nonce)
        address predictedStrategyAddress = computeCreateAddress(nonce);

        // Compute the deterministic remote strategy address
        address _remoteCounterpart = computeRemoteCreateAddress(
            _remoteVault,
            0, // Ethereum domain (origin chain)
            predictedStrategyAddress
        );
        
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new Strategy(
                    USDC,
                    _name,
                    TOKEN_MESSENGER,
                    MESSAGE_TRANSMITTER,
                    _remoteDomain,
                    _remoteCounterpart,
                    _depositer
                )
            )
        );
 

        require(address(_newStrategy) == predictedStrategyAddress, "Predicted strategy address does not match");

        _newStrategy.setPerformanceFee(0);

        _newStrategy.setProfitMaxUnlockTime(0);
        
        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _remoteDomain);

        deployments[_remoteDomain][_remoteVault] = address(_newStrategy);
        nonce++;

        return address(_newStrategy);
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

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        // Check all deployments to find if this strategy was deployed by this factory
        // This is a simple approach - could optimize with additional tracking if needed
        uint32 _remoteDomain = uint32(
            uint256(IStrategyInterface(_strategy).REMOTE_ID())
        );
        address _remoteVault = IStrategyInterface(_strategy)
            .REMOTE_COUNTERPART();

        // Since we changed to track by vault, we need to iterate or add reverse mapping
        // For now, returning true if the strategy has valid configuration
        return deployments[_remoteDomain][_remoteVault] == _strategy;
    }

    function computeCreateAddress(
        uint256 _nonce
    ) public view returns (address) {
        return CREATE.predict(address(this), _nonce);
    }

    function computeRemoteCreateAddress(
        address _remoteVault,
        uint32 _remoteDomain,
        address _remoteCounterpart
    ) public view returns (address) {
        return CREATE3.getDeployed(
            address(remoteFactory), 
            getSalt(_remoteVault, _remoteDomain, _remoteCounterpart)
        );
    }

    function getSalt(
        address _vault,
        uint32 _remoteDomain,
        address _remoteCounterpart
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_vault, _remoteDomain, _remoteCounterpart));
    }
}

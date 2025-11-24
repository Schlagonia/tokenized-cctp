// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {AuctionSwapper} from "@periphery/swappers/AuctionSwapper.sol";

/// @notice Base contract for cross-chain strategies on remote chains
/// @dev Provides keeper management, ERC4626 vault interaction, and abstract bridging interface
abstract contract BaseRemoteStrategy is Governance, AuctionSwapper {
    event UpdatedKeeper(address indexed keeper, bool indexed status);

    event UpdatedProfitMaxUnlockTime(uint256 indexed profitMaxUnlockTime);

    event UpdatedIsShutdown(bool indexed isShutdown);

    event Reported(int256 indexed reportProfit);

    modifier onlyKeepers() {
        _requireIsKeeper(msg.sender);
        _;
    }

    function _requireIsKeeper(address _sender) internal view virtual {
        require(_sender == governance || keepers[_sender], "NotKeeper");
    }

    /// @notice Remote chain identifier for the origin chain
    bytes32 public immutable REMOTE_ID;

    /// @notice Address of the origin strategy counterpart
    address public immutable REMOTE_COUNTERPART;

    /// @notice The asset token for this strategy
    ERC20 public immutable asset;

    /// @notice Tracks assets for profit/loss calculations
    uint256 public deployedAssets;

    /// @notice Used to match TokenizedStrategy interface for triggers.
    uint256 public profitMaxUnlockTime;

    /// @notice Used to match TokenizedStrategy interface for triggers.
    uint256 public lastReport;

    /// @notice Serves as a "pausable" but matches abi of TokenizedStrategy for triggers.
    bool public isShutdown;

    /// @notice Addresses authorized to perform keeper operations
    mapping(address => bool) public keepers;

    constructor(
        address _asset,
        address _governance,
        bytes32 _remoteId,
        address _remoteCounterpart
    ) Governance(_governance) {
        require(_asset != address(0), "ZeroAddress");
        require(_remoteCounterpart != address(0), "ZeroAddress");
        // Note: _remoteId can be 0 for some chains (e.g., Ethereum domain = 0)

        asset = ERC20(_asset);
        REMOTE_ID = _remoteId;
        REMOTE_COUNTERPART = _remoteCounterpart;
        lastReport = block.timestamp;
        profitMaxUnlockTime = 7 days;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Send exposure report to origin chain
    /// @dev Calculates profit/loss and bridges message back
    /// @return reportProfit The profit/loss reported to the origin chain
    function report()
        external
        virtual
        onlyKeepers
        returns (int256 reportProfit)
    {
        require(block.timestamp > lastReport, "NotReady");

        uint256 newDeployedAssets = valueOfDeployedAssets();

        reportProfit = _toInt256(newDeployedAssets) - _toInt256(deployedAssets);

        uint256 idle = balanceOfAsset();
        if (idle > 0 && !isShutdown) {
            newDeployedAssets += _pushFunds(idle);
        }

        // Update State
        lastReport = block.timestamp;
        deployedAssets = newDeployedAssets;

        if (reportProfit != 0) {
            bytes memory messageBody = abi.encode(reportProfit);
            _bridgeMessage(messageBody);
        }

        emit Reported(reportProfit);
    }

    function tend() external virtual onlyKeepers {
        _tend(balanceOfAsset());
    }

    /**
     * @notice Returns if tend() should be called by a keeper.
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     * @return . Calldata for the tend call.
     */
    function tendTrigger() external view virtual returns (bool, bytes memory) {
        return (
            // Return the status of the tend trigger.
            _tendTrigger(),
            // And the needed calldata either way.
            abi.encodeWithSelector(this.tend.selector)
        );
    }

    /// @notice Process withdrawal request from origin chain
    /// @dev Withdraws from vault if needed and bridges tokens back
    /// @param _amount Amount to withdraw and bridge back
    function processWithdrawal(uint256 _amount) external virtual onlyKeepers {
        if (_amount == 0) return;

        uint256 loose = balanceOfAsset();
        // Cannot withdraw unaccounted for profit/loss
        uint256 available = loose + deployedAssets;

        if (_amount > available) {
            _amount = available;
        }

        if (_amount > loose) {
            uint256 withdrawn = _pullFunds(_amount - loose);
            deployedAssets -= withdrawn;

            if (withdrawn < _amount - loose) {
                _amount = loose + withdrawn;
            }
        }

        require(balanceOfAsset() >= _amount, "not enough");

        _bridgeAssets(_amount);
    }

    /// @notice Push loose funds into the vault
    /// @param _amount Amount to deposit into vault
    function pushFunds(uint256 _amount) external virtual onlyKeepers {
        require(!isShutdown, "Shutdown");
        deployedAssets += _pushFunds(_amount);
    }

    /// @notice Pull funds from the vault
    /// @param _amount Amount of shares to redeem from vault
    function pullFunds(uint256 _amount) external virtual onlyKeepers {
        deployedAssets -= _pullFunds(_amount);
    }

    /// @notice Set keeper status for an address
    /// @param _address Address to update
    /// @param _allowed Whether address should have keeper privileges
    function setKeeper(
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        keepers[_address] = _allowed;

        emit UpdatedKeeper(_address, _allowed);
    }

    function setAuction(address _auction) external onlyGovernance {
        _setAuction(_auction);
    }

    function setProfitMaxUnlockTime(
        uint256 _profitMaxUnlockTime
    ) external onlyGovernance {
        profitMaxUnlockTime = _profitMaxUnlockTime;

        emit UpdatedProfitMaxUnlockTime(_profitMaxUnlockTime);
    }

    function setIsShutdown(bool _isShutdown) external onlyGovernance {
        isShutdown = _isShutdown;

        emit UpdatedIsShutdown(_isShutdown);
    }

    //////////////////////////////////////////////////////////////
    //                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////

    function _toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "must be positive");
        return uint256(value);
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(
            value <= uint256(type(int256).max),
            "does not fit in an int256"
        );
        return int256(value);
    }

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT METHODS TO IMPLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate total assets held (vault + loose)
    function totalAssets() public view virtual returns (uint256) {
        return balanceOfAsset() + valueOfDeployedAssets();
    }

    function balanceOfAsset() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function valueOfDeployedAssets() public view virtual returns (uint256);

    function _pushFunds(uint256 _amount) internal virtual returns (uint256);

    function _pullFunds(uint256 _amount) internal virtual returns (uint256);

    function _tend(uint256 _idleAssets) internal virtual {
        deployedAssets += _pushFunds(_idleAssets);
    }

    function _tendTrigger() internal view virtual returns (bool) {
        return false;
    }

    /// @notice Bridge assets back to origin chain
    /// @dev Implementation must handle bridge-specific token transfer logic
    /// @param _amount Amount of tokens to bridge back
    function _bridgeAssets(uint256 _amount) internal virtual returns (uint256);

    /// @notice Send message to origin chain without tokens
    /// @dev Implementation must handle bridge-specific message sending
    /// @param data Encoded message data (typically includes request ID and profit/loss)
    function _bridgeMessage(bytes memory data) internal virtual;
}

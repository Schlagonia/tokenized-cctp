// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {AuctionSwapper} from "@periphery/swappers/AuctionSwapper.sol";

/// @notice Base contract for cross-chain strategies on remote chains
/// @dev Provides keeper, management, accounting and abstract bridging interface
abstract contract BaseRemoteStrategy is Governance, AuctionSwapper {
    event Reported(uint256 indexed totalAssets);

    event WithdrawProcessed(uint256 indexed amount);

    event UpdatedIsShutdown(bool indexed isShutdown);

    event UpdatedAmountToTend(uint256 indexed amountToTend);

    event UpdatedKeeper(address indexed keeper, bool indexed status);

    event UpdatedProfitMaxUnlockTime(uint256 indexed profitMaxUnlockTime);

    modifier onlyKeepers() {
        _requireIsKeeper(msg.sender);
        _;
    }

    modifier isReady() {
        require(block.timestamp > lastReport, "NotReady");
        _;
        lastReport = block.timestamp;
    }

    function _requireIsKeeper(address _sender) internal view virtual {
        require(_sender == governance || keepers[_sender], "NotKeeper");
    }

    /// @notice The asset token for this strategy
    ERC20 public immutable asset;

    /// @notice Remote chain identifier for the origin chain
    bytes32 public immutable REMOTE_ID;

    /// @notice Address of the origin strategy counterpart
    address public immutable REMOTE_COUNTERPART;

    /// @notice Serves as a "pausable" but matches abi of TokenizedStrategy for triggers.
    bool public isShutdown;

    /// @notice Used to match TokenizedStrategy interface for triggers.
    uint256 public lastReport;

    /// @notice Amount of assets to trigger the keepers to tend.
    /// @dev Default is type(uint256).max which disables automatic tend triggers.
    ///      Set via setAmountToTend() to enable.
    uint256 public amountToTend;

    /// @notice Used to match TokenizedStrategy interface for triggers.
    uint256 public profitMaxUnlockTime;

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
        amountToTend = type(uint256).max;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Send exposure report to origin chain
    /// @dev Calculates profit/loss and bridges message back
    /// @return _totalAssets The total assets reported to the origin chain
    /// @return . We return nothing, but need parity with TokenizedStrategy interface.
    function report()
        external
        virtual
        isReady
        onlyKeepers
        returns (uint256 _totalAssets, uint256)
    {
        uint256 idle = balanceOfAsset();
        if (idle > 0 && !isShutdown) {
            _pushFunds(idle);
        }

        _totalAssets = totalAssets();

        bytes memory messageBody = abi.encode(_totalAssets);
        _bridgeMessage(messageBody);

        emit Reported(_totalAssets);
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
    /// @dev Withdraws from vault if needed and bridges tokens back.
    ///      Automatically caps withdrawal to (loose + deployed) assets if requested amount exceeds available.
    /// @param _amount Amount to withdraw and bridge back
    function processWithdrawal(
        uint256 _amount
    ) external virtual onlyKeepers isReady {
        if (_amount == 0) return;

        uint256 loose = balanceOfAsset();
        // Cannot withdraw unaccounted for profit/loss
        uint256 available = loose + valueOfDeployedAssets();

        if (_amount > available) {
            _amount = available;
        }

        if (_amount > loose) {
            uint256 needed = _amount - loose;
            uint256 withdrawn = _pullFunds(needed);

            if (withdrawn < needed) {
                _amount = loose + withdrawn;
            }
        }

        require(balanceOfAsset() >= _amount, "not enough");

        uint256 bridged = _bridgeAssets(_amount);

        emit WithdrawProcessed(bridged);

        // Send a report of the now current assets as well so accounting is correct.
        uint256 _totalAssets = totalAssets();

        bytes memory messageBody = abi.encode(_totalAssets);
        _bridgeMessage(messageBody);

        emit Reported(_totalAssets);
    }

    /// @notice Push loose funds into the vault
    /// @param _amount Amount to deposit into vault
    function pushFunds(
        uint256 _amount
    ) external virtual onlyKeepers returns (uint256) {
        require(!isShutdown, "Shutdown");
        return _pushFunds(_amount);
    }

    /// @notice Pull funds from the vault
    /// @param _amount Amount of assets to withdraw from vault
    function pullFunds(
        uint256 _amount
    ) external virtual onlyKeepers returns (uint256) {
        return _pullFunds(_amount);
    }

    /// @notice Override to make permissioned auction kick.
    function kickAuction(
        address _token
    ) external virtual override onlyKeepers returns (uint256) {
        return _kickAuction(_token);
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

    function setAuction(address _auction) external virtual onlyGovernance {
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

    function setAmountToTend(uint256 _amountToTend) external onlyGovernance {
        amountToTend = _amountToTend;

        emit UpdatedAmountToTend(_amountToTend);
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

    /// @dev Should round down when applicable to avoid dust losses.
    function valueOfDeployedAssets() public view virtual returns (uint256);

    function _pushFunds(uint256 _amount) internal virtual returns (uint256);

    /// @dev Must return the exact amount of assets withdrawn.
    function _pullFunds(uint256 _amount) internal virtual returns (uint256);

    function _tend(uint256 _idleAssets) internal virtual {
        require(!isShutdown, "Shutdown");
        _pushFunds(_idleAssets);
    }

    function _tendTrigger() internal view virtual returns (bool) {
        if (isShutdown) return false;
        return balanceOfAsset() > amountToTend;
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

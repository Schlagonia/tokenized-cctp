// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Governance} from "@periphery/utils/Governance.sol";

/// @notice Base contract for cross-chain strategies on remote chains
/// @dev Provides keeper management, ERC4626 vault interaction, and abstract bridging interface
abstract contract BaseRemoteStrategy is Governance {
    using SafeERC20 for ERC20;

    event UpdatedKeeper(address indexed keeper, bool indexed status);

    /// @notice Remote chain identifier for the origin chain
    bytes32 public immutable REMOTE_ID;

    /// @notice Address of the origin strategy counterpart
    address public immutable REMOTE_COUNTERPART;

    /// @notice The asset token for this strategy
    ERC20 public immutable asset;

    /// @notice The ERC4626 vault where assets are deployed
    IERC4626 public immutable vault;

    /// @notice Counter for ordering cross-chain messages
    uint256 public nextRequestId;

    /// @notice Tracks assets for profit/loss calculations
    uint256 public trackedAssets;

    /// @notice Mapping to prevent message replay and enforce ordering
    mapping(uint256 => bool) public messageProcessed;

    /// @notice Addresses authorized to perform keeper operations
    mapping(address => bool) public keepers;

    modifier onlyKeepers() {
        _requireIsKeeper(msg.sender);
        _;
    }

    function _requireIsKeeper(address _sender) internal view virtual {
        require(_sender == governance || keepers[_sender], "NotKeeper");
    }

    constructor(
        address _asset,
        address _vault,
        address _governance,
        bytes32 _remoteId,
        address _remoteCounterpart
    ) Governance(_governance) {
        require(_asset != address(0), "ZeroAddress");
        require(_vault != address(0), "ZeroAddress");
        require(_remoteCounterpart != address(0), "ZeroAddress");
        // Note: _remoteId can be 0 for some chains (e.g., Ethereum domain = 0)

        asset = ERC20(_asset);
        vault = IERC4626(_vault);
        REMOTE_ID = _remoteId;
        REMOTE_COUNTERPART = _remoteCounterpart;

        // Start ID's at 1 so ordered checks work
        nextRequestId = 1;
        messageProcessed[0] = true;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Send exposure report to origin chain
    /// @dev Calculates profit/loss and bridges message back
    /// @return reportProfit The profit/loss reported to the origin chain
    function sendReport() external onlyKeepers returns (int256 reportProfit) {
        uint256 newTotalAssets = totalAssets();
        reportProfit = int256(newTotalAssets) - int256(trackedAssets);

        bytes memory messageBody = abi.encode(nextRequestId, reportProfit);

        nextRequestId++;

        _bridgeMessage(messageBody);

        trackedAssets = newTotalAssets;
    }

    /// @notice Process withdrawal request from origin chain
    /// @dev Withdraws from vault if needed and bridges tokens back
    /// @param _amount Amount to withdraw and bridge back
    function processWithdrawal(uint256 _amount) external onlyKeepers {
        if (_amount == 0) return;

        uint256 available = totalAssets();
        uint256 loose = asset.balanceOf(address(this));

        if (_amount > available) {
            _amount = available;
        }

        if (_amount > loose) {
            uint256 withdrawn = vault.redeem(
                Math.min(
                    vault.maxRedeem(address(this)),
                    vault.previewWithdraw(_amount - loose)
                ),
                address(this),
                address(this)
            );

            if (withdrawn < _amount - loose) {
                _amount = loose + withdrawn;
            }
        }

        uint256 balance = asset.balanceOf(address(this));
        require(balance >= _amount, "not enough");

        bytes memory messageBody = abi.encode(nextRequestId, -int256(_amount));

        nextRequestId++;

        uint256 bridged = _bridgeAssets(_amount, messageBody);

        trackedAssets -= bridged;
    }

    /// @notice Push loose funds into the vault
    /// @param _amount Amount to deposit into vault
    function pushFunds(uint256 _amount) external onlyKeepers {
        vault.deposit(_amount, address(this));
    }

    /// @notice Pull funds from the vault
    /// @param _shares Amount of shares to redeem from vault
    function pullFunds(uint256 _shares) external onlyKeepers {
        vault.redeem(_shares, address(this), address(this));
    }

    /// @notice Set keeper status for an address
    /// @param _address Address to update
    /// @param _allowed Whether address should have keeper privileges
    function setKeeper(
        address _address,
        bool _allowed
    ) external onlyGovernance {
        keepers[_address] = _allowed;

        emit UpdatedKeeper(_address, _allowed);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle incoming deposit from origin chain
    /// @dev Validates message ordering, deposits to vault, updates tracking
    /// @param requestId The unique identifier for this message
    /// @param _amount Amount of assets received (must be positive)
    function _handleIncomingMessage(
        uint256 requestId,
        int256 _amount
    ) internal virtual {
        require(_amount > 0, "InvalidAmount");
        uint256 amount = uint256(_amount);

        require(
            !messageProcessed[requestId],
            "BaseRemoteStrategy: Message already processed"
        );
        require(
            messageProcessed[requestId - 1],
            "BaseRemoteStrategy: Invalid request ID"
        );

        require(
            asset.balanceOf(address(this)) >= amount,
            "InsufficientBalance"
        );

        // Deposit up to max into vault
        vault.deposit(
            Math.min(amount, vault.maxDeposit(address(this))),
            address(this)
        );

        // Add all added funds to tracked assets
        trackedAssets = uint256(int256(trackedAssets) + _amount);

        // Mark message as processed
        messageProcessed[requestId] = true;
    }

    /// @notice Calculate total assets held (vault + loose)
    function totalAssets() public view returns (uint256) {
        return vaultAssets() + asset.balanceOf(address(this));
    }

    /// @notice Calculate assets deployed in vault
    function vaultAssets() public view returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT METHODS TO IMPLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge assets back to origin chain
    /// @dev Implementation must handle bridge-specific token transfer logic
    /// @param amount Amount of tokens to bridge back
    /// @param data Bridge-specific encoded data (typically includes request ID and negative amount)
    function _bridgeAssets(
        uint256 amount,
        bytes memory data
    ) internal virtual returns (uint256);

    /// @notice Send message to origin chain without tokens
    /// @dev Implementation must handle bridge-specific message sending
    /// @param data Encoded message data (typically includes request ID and profit/loss)
    function _bridgeMessage(bytes memory data) internal virtual;
}

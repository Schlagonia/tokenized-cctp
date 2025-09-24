// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITokenMessenger} from "./interfaces/circle/ITokenMessenger.sol";
import {IMessageTransmitter} from "./interfaces/circle/IMessageTransmitter.sol";
import {BaseCCTP} from "./BaseCCTP.sol";
import {Governance} from "@periphery/utils/Governance.sol";

contract RemoteStrategy is BaseCCTP, Governance {
    using SafeERC20 for ERC20;

    event UpdatedKeeper(address indexed keeper, bool indexed status);

    modifier onlyKeepers() {
        _requireIsKeeper(msg.sender);
        _;
    }

    function _requireIsKeeper(address _sender) internal view virtual {
        require(_sender == governance || keepers[_sender], "NotKeeper");
    }

    ERC20 public immutable asset;

    IERC4626 public immutable vault;

    uint256 public trackedAssets;

    mapping(address => bool) public keepers;

    constructor(
        address _asset,
        address _vault,
        address _governance,
        address _tokenMessenger,
        address _messageTransmitter,
        uint32 _sourceDomain,
        address _remoteCounterpart
    )
        Governance(_governance)
        BaseCCTP(
            _tokenMessenger,
            _messageTransmitter,
            _sourceDomain,
            _remoteCounterpart
        )
    {
        asset = ERC20(_asset);
        vault = IERC4626(_vault);

        asset.forceApprove(_tokenMessenger, type(uint256).max);
        asset.forceApprove(_vault, type(uint256).max);
    }

    function _receiveMessage(int256 _amount) internal override {
        require(_amount > 0, "InvalidAmount");
        uint256 amount = uint256(_amount);
        require(
            asset.balanceOf(address(this)) >= amount,
            "InsufficientBalance"
        );

        // Deposit up to max
        vault.deposit(
            Math.min(amount, vault.maxDeposit(address(this))),
            address(this)
        );

        // Add all added funds to tracked assets
        trackedAssets = uint256(int256(trackedAssets) + _amount);
    }

    function sendExposureReport() external onlyKeepers {
        _sendExposureReport();
    }

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

        bytes memory hookData = abi.encode(nextRequestId, -int256(_amount));

        nextRequestId++;

        TOKEN_MESSENGER.depositForBurnWithHook(
            _amount,
            REMOTE_DOMAIN,
            _addressToBytes32(REMOTE_COUNTERPART),
            address(asset),
            bytes32(0),
            0,
            FINALITY_THRESHOLD_FINALIZED,
            hookData
        );

        trackedAssets -= _amount;
    }

    function _sendExposureReport() internal {
        uint256 newTotalAssets = totalAssets();
        int256 amount = int256(newTotalAssets) - int256(trackedAssets);

        bytes memory messageBody = abi.encode(nextRequestId, amount);

        nextRequestId++;

        MESSAGE_TRANSMITTER.sendMessage(
            REMOTE_DOMAIN,
            _addressToBytes32(REMOTE_COUNTERPART),
            bytes32(0),
            FINALITY_THRESHOLD_FINALIZED,
            messageBody
        );

        trackedAssets = newTotalAssets;
    }

    function totalAssets() internal view returns (uint256) {
        return vaultAssets() + asset.balanceOf(address(this));
    }

    function vaultAssets() internal view returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }

    function setKeeper(
        address _address,
        bool _allowed
    ) external onlyGovernance {
        keepers[_address] = _allowed;

        emit UpdatedKeeper(_address, _allowed);
    }

    function pushFunds(uint256 _amount) external onlyKeepers {
        vault.deposit(_amount, address(this));
    }

    function pullFunds(uint256 _shares) external onlyKeepers {
        vault.redeem(_shares, address(this), address(this));
    }
}

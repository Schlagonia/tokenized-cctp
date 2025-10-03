// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseCrossChain} from "./IBaseCrossChain.sol";
import {IBaseCCTP} from "./IBaseCCTP.sol";

interface IStrategyInterface is IBaseCrossChain, IBaseCCTP {}

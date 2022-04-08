// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

import '../../interfaces/ILegionMetadataStore.sol';
import '../../interfaces/IStakingRules.sol';

import "../HarvesterError.sol";

contract PartsStakingRules is IStakingRules, AccessControlEnumerable {
    bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");

    uint256 public staked;
    uint256 public maxStakeable;

    event MaxStakeableUpdate(uint256 maxStakeable);

    constructor(address _admin) {
        // TODO: setup roles
        _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
        _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);
    }

    /// @inheritdoc IStakingRules
    function canStake(address, address, uint256, uint256 _amount)
        external
        override
        onlyRole(STAKING_RULES_ADMIN_ROLE)
    {
        if (staked + _amount > maxStakeable) revert("MaxStakeable()");

        staked += _amount;
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address, address, uint256, uint256 _amount) external override {
        staked -= _amount;
    }

    /// @inheritdoc IStakingRules
    function getBoost(address, address, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    // ADMIN

    function setMaxStakeable(uint256 _maxStakeable) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        maxStakeable = _maxStakeable;
        emit MaxStakeableUpdate(_maxStakeable);
    }
}

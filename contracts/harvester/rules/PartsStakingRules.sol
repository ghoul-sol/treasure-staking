// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

import '../../interfaces/ILegionMetadataStore.sol';
import '../../interfaces/IStakingRules.sol';

contract PartsStakingRules is IStakingRules, AccessControlEnumerable {
    bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");

    uint256 public staked;
    uint256 public maxStakeableTotal;
    uint256 public maxStakeablePerUser;

    mapping(address => uint256) public getAmountStaked;

    event MaxStakeableUpdate(uint256 maxStakeableTotal);
    event MaxStakeablePerUserUpdate(uint256 maxStakeablePerUser);

    constructor(address _admin, uint256 _maxStakeableTotal, uint256 _maxStakeablePerUser) {
        // TODO: setup roles
        _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
        _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);

        _setMaxStakeableTotal(_maxStakeableTotal);
        _setMaxStakeablePerUser(_maxStakeablePerUser);

    }

    /// @inheritdoc IStakingRules
    function canStake(address _user, address, uint256, uint256 _amount)
        external
        override
        onlyRole(STAKING_RULES_ADMIN_ROLE)
    {
        uint256 stakedCache = staked;
        if (stakedCache + _amount > maxStakeableTotal) revert("MaxStakeable()");
        staked = stakedCache + _amount;

        uint256 amountStakedCache = getAmountStaked[_user];
        if (amountStakedCache + _amount > maxStakeablePerUser) revert("MaxStakeablePerUser()");
        getAmountStaked[_user] = amountStakedCache + _amount;
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address _user, address, uint256, uint256 _amount) external override {
        staked -= _amount;
        getAmountStaked[_user] -= _amount;
    }

    /// @inheritdoc IStakingRules
    function getBoost(address, address, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    // ADMIN

    function setMaxStakeableTotal(uint256 _maxStakeableTotal) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        _setMaxStakeableTotal(_maxStakeableTotal);
    }

    function setMaxStakeablePerUser(uint256 _maxStakeablePerUser) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        _setMaxStakeablePerUser(_maxStakeablePerUser);
    }

    function _setMaxStakeableTotal(uint256 _maxStakeableTotal) internal {
        maxStakeableTotal = _maxStakeableTotal;
        emit MaxStakeableUpdate(_maxStakeableTotal);
    }

    function _setMaxStakeablePerUser(uint256 _maxStakeablePerUser) internal {
        maxStakeablePerUser = _maxStakeablePerUser;
        emit MaxStakeablePerUserUpdate(_maxStakeablePerUser);
    }
}

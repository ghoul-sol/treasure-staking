// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

import '../../interfaces/IStakingRules.sol';

import '../lib/Constant.sol';

abstract contract StakingRulesBase is IStakingRules, AccessControlEnumerable {
    bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    constructor(address _admin, address _nftHandler) {
        _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
        _setRoleAdmin(STAKER_ROLE, STAKING_RULES_ADMIN_ROLE);

        _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);
        _grantRole(STAKER_ROLE, _nftHandler);
    }

    /// @inheritdoc IStakingRules
    function canStake(address _user, address _nft, uint256 _tokenId, uint256 _amount)
        external
        override
        onlyRole(STAKER_ROLE)
    {
        _canStake(_user, _nft, _tokenId, _amount);
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount)
        external
        override
        onlyRole(STAKER_ROLE)
    {
        _canUnstake(_user, _nft, _tokenId, _amount);
    }

    /// @dev it's meant to be overriden by staking rules implementation
    function _canStake(address, address, uint256, uint256) internal virtual {}

    /// @dev it's meant to be overriden by staking rules implementation
    function _canUnstake(address, address, uint256, uint256) internal virtual {}
}

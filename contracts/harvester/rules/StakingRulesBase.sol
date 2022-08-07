// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';

import '../interfaces/IStakingRules.sol';
import '../interfaces/INftHandler.sol';

import '../lib/Constant.sol';

abstract contract StakingRulesBase is IStakingRules, AccessControlEnumerableUpgradeable {
    bytes32 public constant SR_ADMIN = keccak256("SR_ADMIN");
    bytes32 public constant SR_NFT_HANDLER = keccak256("SR_NFT_HANDLER");
    /// @dev temporary role assigned to harvester factory to setup nftHandler after it's deployed
    ///      (solves circular dependency)
    bytes32 public constant SR_HARVESTER_FACTORY = keccak256("SR_HARVESTER_FACTORY");

    INftHandler public nftHandler;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function _initStakingRulesBase(address _admin, address _harvesterFactory) internal onlyInitializing {
        __AccessControlEnumerable_init();

        _setRoleAdmin(SR_ADMIN, SR_ADMIN);
        _setRoleAdmin(SR_NFT_HANDLER, SR_ADMIN);
        _setRoleAdmin(SR_HARVESTER_FACTORY, SR_ADMIN);

        _grantRole(SR_ADMIN, _admin);
        // SR_NFT_HANDLER must be a contract that implements harvester() getter
        _grantRole(SR_HARVESTER_FACTORY, _harvesterFactory);
    }

    /// @inheritdoc IStakingRules
    function canStake(address _user, address _nft, uint256 _tokenId, uint256 _amount)
        external
        override
        onlyRole(SR_NFT_HANDLER)
    {
        _canStake(_user, _nft, _tokenId, _amount);
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount)
        external
        override
        onlyRole(SR_NFT_HANDLER)
    {
        _canUnstake(_user, _nft, _tokenId, _amount);
    }

    /// @inheritdoc IStakingRules
    function setNftHandler(address _nftHandler) external onlyRole(SR_HARVESTER_FACTORY) {
        nftHandler = INftHandler(_nftHandler);

        _grantRole(SR_NFT_HANDLER, _nftHandler);
        _revokeRole(SR_HARVESTER_FACTORY, msg.sender);
    }

    /// @dev it's meant to be overriden by staking rules implementation
    function _canStake(address, address, uint256, uint256) internal virtual {}

    /// @dev it's meant to be overriden by staking rules implementation
    function _canUnstake(address, address, uint256, uint256) internal virtual {}
}

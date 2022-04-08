// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/utils/Counters.sol';

import '../../interfaces/ILegionMetadataStore.sol';
import '../../interfaces/IExtractorStakingRules.sol';

import "../HarvesterError.sol";

contract ExtractorStakingRules is IExtractorStakingRules, AccessControlEnumerable {
    using Counters for Counters.Counter;

    struct ExtractorData {
        uint256 tokenId;
        uint256 stakedTimestamp;
    }

    bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");

    uint256 public maxStakeable;

    /// @dev time in seconds during which extractor is live
    uint256 public lifetime;

    /// @dev array of spot Id(s)
    Counters.Counter public extractorCount;
    /// @dev maps spot Id to ExtractorData
    mapping(uint256 => ExtractorData) public stakedExtractor;

    /// @dev maps token Id to boost value
    mapping(uint256 => uint256) public extractorBoost;

    event MaxStakeableUpdate(uint256 maxStakeable);
    event ExtractorBoostUpdate(uint256 tokenId, uint256 boost);
    event ExtractorStaked(uint256 tokenId, uint256 amount);

    constructor(address _admin) {
        // TODO: setup roles
        _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
        _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);
    }

    function isExtractorActive(uint256 _spotId) public view returns (bool) {
        return block.timestamp <= stakedExtractor[_spotId].stakedTimestamp + lifetime;
    }

    /// @return extractors array of all staked extractors
    function getExtractors() external view returns (ExtractorData[] memory extractors) {
        extractors = new ExtractorData[](extractorCount.current());

        for (uint256 i = 0; i < extractors.length; i++) {
            extractors[i] = stakedExtractor[i];
        }
    }

    /// @return totalBoost boost sum of all active extractors
    function getExtractorsTotalBoost() external view returns (uint256 totalBoost) {
        for (uint256 i = 0; i < extractorCount.current(); i++) {
            if (isExtractorActive(i)) {
                totalBoost += extractorBoost[stakedExtractor[i].tokenId];
            }
        }
    }

    /// @inheritdoc IStakingRules
    function canStake(address, address, uint256 _tokenId, uint256 _amount)
        external
        override
        onlyRole(STAKING_RULES_ADMIN_ROLE)
    {
        if (extractorCount.current() + _amount > maxStakeable) revert("MaxStakeable()");

        for (uint256 i = 0; i < _amount; i++) {
            uint256 spotId = extractorCount.current();

            stakedExtractor[spotId] = ExtractorData(_tokenId, block.timestamp);
            extractorCount.increment();
        }
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address, address, uint256, uint256) external pure override {
        revert("CannotUnstake()");
    }

    /// @inheritdoc IExtractorStakingRules
    function canReplace(address, address, uint256 _tokenId, uint256 _amount, uint256 _replacedSpotId)
        external
        override
        onlyRole(STAKING_RULES_ADMIN_ROLE)
        returns (uint256 replacedTokenId, uint256 replacedAmount)
    {
        if (_amount != 1) revert("MustReplaceOne()");

        replacedTokenId = stakedExtractor[_replacedSpotId].tokenId;
        replacedAmount = _amount;

        if (isExtractorActive(_replacedSpotId)) {
            uint256 oldBoost = extractorBoost[replacedTokenId];
            uint256 newBoost = extractorBoost[_tokenId];
            if (oldBoost >= newBoost) revert("MustReplaceWithHigherBoost()");
        }

        stakedExtractor[_replacedSpotId] = ExtractorData(_tokenId, block.timestamp);
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

    function setExtractorBoost(uint256 _tokenId, uint256 _boost) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        extractorBoost[_tokenId] = _boost;
        emit ExtractorBoostUpdate(_tokenId, _boost);
    }
}

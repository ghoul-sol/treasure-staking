// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

import '../../interfaces/ILegionMetadataStore.sol';
import '../../interfaces/IStakingRules.sol';

import '../lib/Constant.sol';

contract LegionStakingRules is IStakingRules, AccessControlEnumerable {
    bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");

    uint256[][] public legionBoostMatrix;
    uint256[][] public legionWeightMatrix;
    uint256[][] public legionRankMatrix;

    ILegionMetadataStore public legionMetadataStore;

    /// @dev maps user wallet to current staked weight. For weight values, see getWeight
    mapping (address => uint256) public weightStaked;

    uint256 public maxLegionWeight;
    uint256 public staked;
    uint256 public maxStakeableTotal;
    uint256 public totalRank;
    uint256 public boostFactor;

    event MaxWeightUpdate(uint256 maxLegionWeight);
    event LegionMetadataStoreUpdate(ILegionMetadataStore legionMetadataStore);
    event LegionBoostMatrixUpdate(uint256[][] legionBoostMatrix);
    event LegionWeightMatrixUpdate(uint256[][] legionWeightMatrix);
    event LegionRankMatrixUpdate(uint256[][] legionRankMatrix);
    event MaxStakeableTotalUpdate(uint256 maxStakeableTotal);
    event BoostFactorUpdate(uint256 boostFactor);

    constructor(
        address _admin,
        ILegionMetadataStore _legionMetadataStore,
        uint256 _maxLegionWeight,
        uint256 _maxStakeableTotal,
        uint256 _boostFactor
    ) {
        // TODO: setup roles
        _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
        _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);

        legionMetadataStore = _legionMetadataStore;

        _setMaxWeight(_maxLegionWeight);
        _setMaxStakeableTotal(_maxStakeableTotal);
        _setBoostFactor(_boostFactor);

        // array follows values from ILegionMetadataStore.LegionGeneration and ILegionMetadataStore.LegionRarity
        legionBoostMatrix = [
            // GENESIS
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(600e16), uint256(200e16), uint256(75e16), uint256(100e16), uint256(50e16), uint256(0)],
            // AUXILIARY
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(0), uint256(25e16), uint256(0), uint256(10e16), uint256(5e16), uint256(0)],
            // RECRUIT
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)]
        ];

        uint256 illegalWeight = _maxLegionWeight * 1e18;

        legionWeightMatrix = [
            // GENESIS
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(120e18), uint256(40e18), uint256(15e18), uint256(20e18), uint256(10e18), illegalWeight],
            // AUXILIARY
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalWeight, uint256(55e17), illegalWeight, uint256(4e18), uint256(25e17), illegalWeight],
            // RECRUIT
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalWeight, illegalWeight, illegalWeight, illegalWeight, illegalWeight, illegalWeight]
        ];

        uint256 illegalRank = 1e18;

        legionRankMatrix = [
            // GENESIS
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(4e18), uint256(4e18), uint256(2e18), uint256(3e18), uint256(1e18), illegalRank],
            // AUXILIARY
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalRank, uint256(3e18), illegalRank, uint256(2e18), uint256(1e18), illegalRank],
            // RECRUIT
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalRank, illegalRank, illegalRank, illegalRank, illegalRank, illegalRank]
        ];
    }

    /// @inheritdoc IStakingRules
    function canStake(address _user, address, uint256 _tokenId, uint256)
        external
        override
        onlyRole(STAKING_RULES_ADMIN_ROLE)
    {
        staked++;
        totalRank += getRank(_tokenId);
        weightStaked[_user] += getWeight(_tokenId);

        if (weightStaked[_user] > maxLegionWeight) revert("MaxWeight()");
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address _user, address, uint256 _tokenId, uint256) external override {
        staked--;
        totalRank -= getRank(_tokenId);
        weightStaked[_user] -= getWeight(_tokenId);
    }

    /// @inheritdoc IStakingRules
    function getUserBoost(address, address, uint256 _tokenId, uint256) external view override returns (uint256) {
        ILegionMetadataStore.LegionMetadata memory metadata = legionMetadataStore.metadataForLegion(_tokenId);

        return getLegionBoost(uint256(metadata.legionGeneration), uint256(metadata.legionRarity));
    }

    /// @inheritdoc IStakingRules
    function getHarvesterBoost() external view returns (uint256) {
        // quadratic function in the interval: [1, (1 + boost_factor)] based on number of parts staked.
        // exhibits diminishing returns on boosts as more legions are added
        // num: number of legions staked on harvester
        // max: number of legions where you achieve max boost
        // avg_legion_rank: avg legion rank on your harvester
        // boost_factor: the amount of boost you want to apply to parts
        // default is 1 = 50% boost (1.5x) if num = max

        uint256 n = (staked > maxStakeableTotal ? maxStakeableTotal : staked) * Constant.ONE;
        uint256 maxLegions = maxStakeableTotal * Constant.ONE;
        uint256 avgLegionRank = totalRank / staked;
        uint256 legionRankModifier = 9e17 + avgLegionRank / 10;
        uint256 boost = boostFactor * Constant.ONE;

        return Constant.ONE + (2 * n - n ** 2 / maxLegions) * legionRankModifier / Constant.ONE * boost / maxLegions;
    }

    function getLegionBoost(uint256 _legionGeneration, uint256 _legionRarity) public view returns (uint256) {
        if (_legionGeneration < legionBoostMatrix.length && _legionRarity < legionBoostMatrix[_legionGeneration].length) {
            return legionBoostMatrix[_legionGeneration][_legionRarity];
        }

        return 0;
    }

    function getRank(uint256 _tokenId) public view returns (uint256) {
        ILegionMetadataStore.LegionMetadata memory metadata = legionMetadataStore.metadataForLegion(_tokenId);
        uint256 _legionGeneration = uint256(metadata.legionGeneration);
        uint256 _legionRarity = uint256(metadata.legionRarity);

        if (_legionGeneration < legionRankMatrix.length && _legionRarity < legionRankMatrix[_legionGeneration].length) {
            return legionRankMatrix[_legionGeneration][_legionRarity];
        }

        return 0;
    }

    function getWeight(uint256 _tokenId) public view returns (uint256) {
        ILegionMetadataStore.LegionMetadata memory metadata = legionMetadataStore.metadataForLegion(_tokenId);
        uint256 _legionGeneration = uint256(metadata.legionGeneration);
        uint256 _legionRarity = uint256(metadata.legionRarity);

        if (_legionGeneration < legionWeightMatrix.length && _legionRarity < legionWeightMatrix[_legionGeneration].length) {
            return legionWeightMatrix[_legionGeneration][_legionRarity];
        }

        return 0;
    }

    // ADMIN

    function setLegionMetadataStore(ILegionMetadataStore _legionMetadataStore) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        legionMetadataStore = _legionMetadataStore;
        emit LegionMetadataStoreUpdate(_legionMetadataStore);
    }

    function setLegionBoostMatrix(uint256[][] memory _legionBoostMatrix) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        legionBoostMatrix = _legionBoostMatrix;
        emit LegionBoostMatrixUpdate(_legionBoostMatrix);
    }

    function setLegionWeightMatrix(uint256[][] memory _legionWeightMatrix) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        legionWeightMatrix = _legionWeightMatrix;
        emit LegionWeightMatrixUpdate(_legionWeightMatrix);
    }

    function setLegionRankMatrix(uint256[][] memory _legionRankMatrix) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        legionRankMatrix = _legionRankMatrix;
        emit LegionRankMatrixUpdate(_legionRankMatrix);
    }

    function setMaxWeight(uint256 _maxLegionWeight) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        _setMaxWeight(_maxLegionWeight);
    }

    function setMaxStakeableTotal(uint256 _maxStakeableTotal) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        _setMaxStakeableTotal(_maxStakeableTotal);
    }

    function setBoostFactor(uint256 _boostFactor) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        _setBoostFactor(_boostFactor);
    }

    function _setMaxWeight(uint256 _maxLegionWeight) internal {
        maxLegionWeight = _maxLegionWeight;
        emit MaxWeightUpdate(_maxLegionWeight);
    }

    function _setMaxStakeableTotal(uint256 _maxStakeableTotal) internal {
        maxStakeableTotal = _maxStakeableTotal;
        emit MaxStakeableTotalUpdate(_maxStakeableTotal);
    }

    function _setBoostFactor(uint256 _boostFactor) internal {
        boostFactor = _boostFactor;
        emit BoostFactorUpdate(_boostFactor);
    }
}

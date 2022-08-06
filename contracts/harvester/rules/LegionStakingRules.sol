// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '../../interfaces/ILegionMetadataStore.sol';

import "./StakingRulesBase.sol";

contract LegionStakingRules is StakingRulesBase {
    uint256 public staked;
    uint256 public maxStakeableTotal;
    uint256 public maxLegionWeight;
    uint256 public totalRank;
    uint256 public boostFactor;

    uint256[][] public legionBoostMatrix;
    uint256[][] public legionWeightMatrix;
    uint256[][] public legionRankMatrix;

    ILegionMetadataStore public legionMetadataStore;

    /// @dev maps user wallet to current staked weight. For weight values, see getWeight
    mapping (address => uint256) public weightStaked;

    event MaxWeight(uint256 maxLegionWeight);
    event LegionMetadataStore(ILegionMetadataStore legionMetadataStore);
    event LegionBoostMatrix(uint256[][] legionBoostMatrix);
    event LegionWeightMatrix(uint256[][] legionWeightMatrix);
    event LegionRankMatrix(uint256[][] legionRankMatrix);
    event MaxStakeableTotal(uint256 maxStakeableTotal);
    event BoostFactor(uint256 boostFactor);

    function init(
        address _admin,
        address _harvesterFactory,
        ILegionMetadataStore _legionMetadataStore,
        uint256 _maxLegionWeight,
        uint256 _maxStakeableTotal,
        uint256 _boostFactor
    ) external initializer {
        _initStakingRulesBase(_admin, _harvesterFactory);

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
            [uint256(120e18), uint256(40e18), uint256(16e18), uint256(21e18), uint256(11e18), illegalWeight],
            // AUXILIARY
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalWeight, uint256(5.5e18), illegalWeight, uint256(4e18), uint256(2.5e18), illegalWeight],
            // RECRUIT
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalWeight, illegalWeight, illegalWeight, illegalWeight, illegalWeight, illegalWeight]
        ];

        uint256 illegalRank = 1e18;

        legionRankMatrix = [
            // GENESIS
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(4e18), uint256(4e18), uint256(2e18), uint256(3e18), uint256(1.5e18), illegalRank],
            // AUXILIARY
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalRank, uint256(1.2e18), illegalRank, uint256(1.1e18), uint256(1e18), illegalRank],
            // RECRUIT
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [illegalRank, illegalRank, illegalRank, illegalRank, illegalRank, illegalRank]
        ];
    }

    function getLegionBoostMatrix() public view returns (uint256[][] memory) {
        return legionBoostMatrix;
    }

    function getLegionWeightMatrix() public view returns (uint256[][] memory) {
        return legionWeightMatrix;
    }

    function getLegionRankMatrix() public view returns (uint256[][] memory) {
        return legionRankMatrix;
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
        if (maxLegions == 0) return Constant.ONE;
        uint256 avgLegionRank = staked == 0 ? 0 : totalRank / staked;
        uint256 legionRankModifier = 0.9e18 + avgLegionRank / 10;

        return Constant.ONE + (2 * n - n ** 2 / maxLegions) * legionRankModifier / Constant.ONE * boostFactor / maxLegions;
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

    function _canStake(address _user, address, uint256 _tokenId, uint256) internal override {
        staked++;
        totalRank += getRank(_tokenId);
        weightStaked[_user] += getWeight(_tokenId);

        if (weightStaked[_user] > maxLegionWeight) revert("MaxWeight()");
    }

    function _canUnstake(address _user, address, uint256 _tokenId, uint256) internal override {
        staked--;
        totalRank -= getRank(_tokenId);
        weightStaked[_user] -= getWeight(_tokenId);
    }

    // ADMIN

    function setLegionMetadataStore(ILegionMetadataStore _legionMetadataStore) external onlyRole(SR_ADMIN) {
        legionMetadataStore = _legionMetadataStore;
        emit LegionMetadataStore(_legionMetadataStore);
    }

    function setLegionBoostMatrix(uint256[][] memory _legionBoostMatrix) external onlyRole(SR_ADMIN) {
        legionBoostMatrix = _legionBoostMatrix;
        emit LegionBoostMatrix(_legionBoostMatrix);
    }

    function setLegionWeightMatrix(uint256[][] memory _legionWeightMatrix) external onlyRole(SR_ADMIN) {
        legionWeightMatrix = _legionWeightMatrix;
        emit LegionWeightMatrix(_legionWeightMatrix);
    }

    /// @dev changing ranks values after NFTs are already staked can break `totalRank` calculations
    function setLegionRankMatrix(uint256[][] memory _legionRankMatrix) external onlyRole(SR_ADMIN) {
        legionRankMatrix = _legionRankMatrix;
        emit LegionRankMatrix(_legionRankMatrix);
    }

    function setMaxWeight(uint256 _maxLegionWeight) external onlyRole(SR_ADMIN) {
        _setMaxWeight(_maxLegionWeight);
    }

    function setMaxStakeableTotal(uint256 _maxStakeableTotal) external onlyRole(SR_ADMIN) {
        _setMaxStakeableTotal(_maxStakeableTotal);
    }

    function setBoostFactor(uint256 _boostFactor) external onlyRole(SR_ADMIN) {
        _setBoostFactor(_boostFactor);
    }

    function _setMaxWeight(uint256 _maxLegionWeight) internal {
        maxLegionWeight = _maxLegionWeight;
        emit MaxWeight(_maxLegionWeight);
    }

    function _setMaxStakeableTotal(uint256 _maxStakeableTotal) internal {
        maxStakeableTotal = _maxStakeableTotal;
        emit MaxStakeableTotal(_maxStakeableTotal);
    }

    function _setBoostFactor(uint256 _boostFactor) internal {
        boostFactor = _boostFactor;
        emit BoostFactor(_boostFactor);
    }
}

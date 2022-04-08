// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

import '../../interfaces/ILegionMetadataStore.sol';
import '../../interfaces/IStakingRules.sol';

import "../HarvesterError.sol";

contract LegionStakingRules is IStakingRules, AccessControlEnumerable {
    bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");

    uint256[][] public legionBoostMatrix;
    uint256[][] public legionWeightMatrix;

    ILegionMetadataStore public legionMetadataStore;

    /// @dev maps user wallet to current staked weight. For weight values, see getWeight
    mapping (address => uint256) public weightStaked;

    uint256 public maxWeight;

    event MaxWeightUpdate(uint256 maxWeight);
    event LegionMetadataStoreUpdate(ILegionMetadataStore legionMetadataStore);
    event LegionBoostMatrixUpdate(uint256[][] legionBoostMatrix);
    event LegionWeightMatrixUpdate(uint256[][] legionWeightMatrix);

    constructor(address _admin, ILegionMetadataStore _legionMetadataStore) {
        // TODO: setup roles
        _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
        _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);

        legionMetadataStore = _legionMetadataStore;

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

        // TODO: update weight matrix
        legionWeightMatrix = [
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
    }

    /// @inheritdoc IStakingRules
    function canStake(address _user, address, uint256 _tokenId, uint256)
        external
        override
        onlyRole(STAKING_RULES_ADMIN_ROLE)
    {
        weightStaked[_user] += getWeight(_tokenId);

        if (weightStaked[_user] > maxWeight) revert("MaxWeight()");
    }

    /// @inheritdoc IStakingRules
    function canUnstake(address, address, uint256, uint256) external pure override {}

    /// @inheritdoc IStakingRules
    function getBoost(address, address, uint256 _tokenId, uint256) external view override returns (uint256) {
        ILegionMetadataStore.LegionMetadata memory metadata = legionMetadataStore.metadataForLegion(_tokenId);

        return getLegionBoost(uint256(metadata.legionGeneration), uint256(metadata.legionRarity));
    }

    function getLegionBoost(uint256 _legionGeneration, uint256 _legionRarity) public view returns (uint256) {
        if (_legionGeneration < legionBoostMatrix.length && _legionRarity < legionBoostMatrix[_legionGeneration].length) {
            return legionBoostMatrix[_legionGeneration][_legionRarity];
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

    function setMaxWeight(uint256 _maxWeight) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
        maxWeight = _maxWeight;
        emit MaxWeightUpdate(_maxWeight);
    }
}

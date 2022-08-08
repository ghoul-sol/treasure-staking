// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/Counters.sol";

import "../interfaces/IExtractorStakingRules.sol";

import "./StakingRulesBase.sol";

contract ExtractorStakingRules is IExtractorStakingRules, StakingRulesBase {
    using Counters for Counters.Counter;

    struct ExtractorData {
        address user;
        uint256 tokenId;
        uint256 stakedTimestamp;
    }

    uint256 public maxStakeable;

    /// @dev time in seconds during which extractor is live
    uint256 public lifetime;

    /// @dev address of NFT extractor token
    address public extractorAddress;

    /// @dev latest spot Id
    Counters.Counter public extractorCount;
    /// @dev maps spot Id to ExtractorData
    mapping(uint256 => ExtractorData) public stakedExtractor;

    /// @dev maps token Id => boost value
    mapping(uint256 => uint256) public extractorBoost;

    event MaxStakeable(uint256 maxStakeable);
    event ExtractorBoost(uint256 tokenId, uint256 boost);
    event ExtractorStaked(uint256 tokenId, uint256 spotId, uint256 amount);
    event ExtractorReplaced(uint256 tokenId, uint256 replacedSpotId);
    event Lifetime(uint256 lifetime);
    event ExtractorAddress(address extractorAddress);

    error InvalidAddress();
    error ZeroAmount();
    error MustReplaceOne();
    error InvalidSpotId();
    error MustReplaceWithHigherBoost();
    error ZeroBoost();
    error MaxStakeableReached();
    error CannotUnstake();

    modifier validateInput(address _nft, uint256 _amount) {
        if (_nft != extractorAddress) revert InvalidAddress();
        if (_amount == 0) revert ZeroAmount();

        _;
    }

    function init(
        address _admin,
        address _harvesterFactory,
        address _extractorAddress,
        uint256 _maxStakeable,
        uint256 _lifetime
    ) external initializer {
        _initStakingRulesBase(_admin, _harvesterFactory);

        _setExtractorAddress(_extractorAddress);
        _setMaxStakeable(_maxStakeable);
        _setExtractorLifetime(_lifetime);
    }

    function isExtractorActive(uint256 _spotId) public view returns (bool) {
        return block.timestamp <= stakedExtractor[_spotId].stakedTimestamp + lifetime;
    }

    function getExtractorCount() public view returns (uint256) {
        return extractorCount.current();
    }

    /// @return extractors array of all staked extractors
    function getExtractors() external view returns (ExtractorData[] memory extractors) {
        extractors = new ExtractorData[](extractorCount.current());

        for (uint256 i = 0; i < extractors.length; i++) {
            extractors[i] = stakedExtractor[i];
        }
    }

    /// @return totalBoost boost sum of all active extractors
    function getExtractorsTotalBoost() public view returns (uint256 totalBoost) {
        for (uint256 i = 0; i < extractorCount.current(); i++) {
            if (isExtractorActive(i)) {
                totalBoost += extractorBoost[stakedExtractor[i].tokenId];
            }
        }
    }

    /// @inheritdoc IStakingRules
    function getUserBoost(address, address, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IStakingRules
    function getHarvesterBoost() external view returns (uint256) {
        return Constant.ONE + getExtractorsTotalBoost();
    }

    /// @inheritdoc IExtractorStakingRules
    function canReplace(address _user, address _nft, uint256 _tokenId, uint256 _amount, uint256 _replacedSpotId)
        external
        override
        onlyRole(SR_NFT_HANDLER)
        validateInput(_nft, _amount)
        returns (address user, uint256 replacedTokenId, uint256 replacedAmount)
    {
        if (_amount != 1) revert MustReplaceOne();
        if (_replacedSpotId >= maxStakeable) revert InvalidSpotId();

        user = stakedExtractor[_replacedSpotId].user;
        replacedTokenId = stakedExtractor[_replacedSpotId].tokenId;
        replacedAmount = _amount;

        if (isExtractorActive(_replacedSpotId)) {
            uint256 oldBoost = extractorBoost[replacedTokenId];
            uint256 newBoost = extractorBoost[_tokenId];
            if (oldBoost >= newBoost) revert MustReplaceWithHigherBoost();
        }

        stakedExtractor[_replacedSpotId] = ExtractorData(_user, _tokenId, block.timestamp);
        emit ExtractorReplaced(_tokenId, _replacedSpotId);
    }

    function _processStake(address _user, address _nft, uint256 _tokenId, uint256 _amount)
        internal
        override
        validateInput(_nft, _amount)
    {
        if (extractorBoost[_tokenId] == 0) revert ZeroBoost();
        if (extractorCount.current() + _amount > maxStakeable) revert MaxStakeableReached();

        uint256 spotId;

        for (uint256 i = 0; i < _amount; i++) {
            spotId = extractorCount.current();

            stakedExtractor[spotId] = ExtractorData(_user, _tokenId, block.timestamp);
            extractorCount.increment();
        }

        emit ExtractorStaked(_tokenId, spotId, _amount);
    }

    function _processUnstake(address, address, uint256, uint256) internal pure override {
        revert CannotUnstake();
    }

    // ADMIN

    function setMaxStakeable(uint256 _maxStakeable) external onlyRole(SR_ADMIN) {
        _setMaxStakeable(_maxStakeable);
    }

    function setExtractorBoost(uint256 _tokenId, uint256 _boost) external onlyRole(SR_ADMIN) {
        nftHandler.harvester().callUpdateRewards();

        extractorBoost[_tokenId] = _boost;
        emit ExtractorBoost(_tokenId, _boost);
    }

    function setExtractorLifetime(uint256 _lifetime) external onlyRole(SR_ADMIN) {
        nftHandler.harvester().callUpdateRewards();

        _setExtractorLifetime(_lifetime);
    }

    function _setMaxStakeable(uint256 _maxStakeable) internal {
        maxStakeable = _maxStakeable;
        emit MaxStakeable(_maxStakeable);
    }

    function _setExtractorAddress(address _extractorAddress) internal {
        extractorAddress = _extractorAddress;
        emit ExtractorAddress(_extractorAddress);
    }

    function _setExtractorLifetime(uint256 _lifetime) internal {
        lifetime = _lifetime;
        emit Lifetime(_lifetime);
    }
}

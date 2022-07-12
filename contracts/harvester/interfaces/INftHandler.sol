// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IHarvester.sol";
import './IStakingRules.sol';

interface INftHandler {
    enum Interfaces { Unsupported, ERC721, ERC1155 }

    struct NftConfig {
        Interfaces supportedInterface;
        /// @dev contract address which calcualtes boost for this NFT
        IStakingRules stakingRules;
    }

    /// @notice Initialize contract
    /// @param _admin wallet address to be set as contract's admin
    /// @param _harvester harvester address for which INftHandler is deployed
    /// @param _nfts array of NFTs allowed to be staked
    /// @param _tokenIds array of tokenIds allowed to be staked, it should correspond to `_nfts`
    /// @param _nftConfigs array of congigs for each NFT
    function init(
        address _admin,
        address _harvester,
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        INftHandler.NftConfig[] memory _nftConfigs
    ) external;

    /// @notice Gets harvester address linked to this contract
    /// @return Harvester interface
    function harvester() external view returns (IHarvester);

    /// @notice Gets staking rules contract address
    /// @param _nft NFT contract address for which to read staking rules contract address
    /// @param _tokenId token id for which to read staking rules contract address
    /// @return staking rules contract address
    function getStakingRules(address _nft, uint256 _tokenId) external view returns (IStakingRules);

    /// @notice Gets cached user boost
    /// @dev Cached boost is re-calculated on the fly on stake and unstake NFT by user
    /// @param _user user's wallet address
    /// @return cached user boost as percentage, 1e18 == 100%
    function getUserBoost(address _user) external view returns (uint256);

    /// @notice Gets given NFT boost for user
    /// @param _user user's wallet address
    /// @param _nft address of NFT contract
    /// @param _tokenId token Id of NFT for which to calcualte the boost
    /// @param _amount amount of tokens for which to calculate boost, must be 1 for ERC721
    /// @return calcualted boost for given NFT for given user as percentage, 1e18 == 100%
    function getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) external view returns (uint256);

    /// @notice Gets harvester boost to calcualte rewards allocation
    /// @return boost calcualted harvester boost to calcualte rewards allocation
    function getHarvesterTotalBoost() external view returns (uint256 boost);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface INftHandler {
    /// @notice Gets staking rules contract address
    /// @param _nft NFT contract address for which to read staking rules contract address
    /// @return staking rules contract address
    function getStakingRules(address _nft) external view returns (address);

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

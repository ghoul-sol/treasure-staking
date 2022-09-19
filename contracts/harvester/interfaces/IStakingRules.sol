// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface IStakingRules {
    /// @notice Checks if NFT can be staked
    /// @param _user wallet that is staking the NFT
    /// @param _nft NFT address, can be either ERC721 or ERC1155
    /// @param _tokenId token Id of staked NFT
    /// @param _amount number of NFTs staked, must be 1 for ERC721
    function processStake(address _user, address _nft, uint256 _tokenId, uint256 _amount) external;

    /// @notice Checks if NFT can be unstaked
    /// @param _user wallet that is unstaking the NFT
    /// @param _nft NFT address, can be either ERC721 or ERC1155
    /// @param _tokenId token Id of unstaked NFT
    /// @param _amount number of NFTs unstaked, must be 1 for ERC721
    function processUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount) external;

    /// @notice Gets amount of boost that user gets by staking given NFT
    /// @param _user wallet for which to calculate boost
    /// @param _nft NFT address, can be either ERC721 or ERC1155
    /// @param _tokenId token Id of NFT
    /// @param _amount number of NFTs for which to calculate boost, must be 1 for ERC721
    /// @return boost amount that user gets by staking NFT(s)
    function getUserBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) external view returns (uint256);

    /// @notice Gets amount of boost that harvester gets for all staked NFTs
    /// @return amount of boost that harvester gets for all staked NFTs
    function getHarvesterBoost() external view returns (uint256);

    /// @notice Set nftHandler address
    /// @param _nftHandler address
    function setNftHandler(address _nftHandler) external;

}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./IStakingRules.sol";

interface IExtractorStakingRules is IStakingRules {
    /// @notice Checks if extractor can be replaced
    /// @param _tokenId token Id of new extractor
    /// @param _amount must be 1, only 1 extractor at a time can be replaced
    /// @param _replacedSpotId index of stakedExtractor mapping for replaced extractor
    /// @return user wallet address that staked replaced NFT
    /// @return replacedTokenId tokenId of replaced NFT
    /// @return replacedAmount amount of replaced NFT, must be 1 for ERC721
    function canReplace(address _user, address _nft, uint256 _tokenId, uint256 _amount, uint256 _replacedSpotId)
        external
        returns (address user, uint256 replacedTokenId, uint256 replacedAmount);
}

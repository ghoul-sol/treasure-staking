// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

error MaxStakeable();

error MaxWeight();

error NftAlreadyStaked(address _nft, uint256 _tokenId);

error InvalidNftAddress(address _nft);

error NothingToStake(uint256 _amount);

error WrongAmountForERC721(uint256 _amount);

error NftNotStaked(address _nft, uint256 _tokenId);

error NftNotAllowed(address _nft);

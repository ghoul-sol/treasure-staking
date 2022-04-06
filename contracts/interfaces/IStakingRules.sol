// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IStakingRules {
    function canStake(address _user, address _nft, uint256 _tokenId, uint256 _amount) external;
    function canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount) external;
    function getBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) external view returns (uint256);
}

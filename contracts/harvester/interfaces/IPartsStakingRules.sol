// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IStakingRules.sol";

interface IPartsStakingRules is IStakingRules {
    /// @notice Gets amount of staked NFTs of given contract
    /// @param _user wallet address for which to read the value
    /// @return number of NFTs staked by `_user`
    function getAmountStaked(address _user) external view returns (uint256);
}

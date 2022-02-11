// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IMiniChefV2 {
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, int256 rewardDebt);
}

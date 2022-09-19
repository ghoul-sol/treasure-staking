// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

interface IMiddleman {
    function requestRewards() external returns (uint256 rewardsPaid);

    function getPendingRewards(address _stream) external view returns (uint256 pendingRewards);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

interface IAtlasMine {
    enum Lock { twoWeeks, oneMonth, threeMonths, sixMonths, twelveMonths }

    function magic() external view returns (IERC20);
    function getAllUserDepositIds(address _user) external view returns (uint256[] memory);
    function userInfo(address _user, uint256 _depositId) external view virtual returns (
        uint256 originalDepositAmount,
        uint256 depositAmount,
        uint256 lpAmount,
        uint256 lockedUntil,
        uint256 vestingLastUpdate,
        int256 rewardDebt,
        Lock lock);
    function getLockBoost(Lock _lock) external pure returns (uint256 boost, uint256 timelock);
    function ONE() external pure returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./INftHandler.sol";

interface IHarvester {
    enum Lock { twoWeeks, oneMonth, threeMonths, sixMonths, twelveMonths }

    struct UserInfo {
        uint256 originalDepositAmount;
        uint256 depositAmount;
        uint256 lockLpAmount;
        uint256 lockedUntil;
        uint256 vestingLastUpdate;
        Lock lock;
    }

    struct CapConfig {
        address parts;
        uint256 capPerPart;
    }

    struct GlobalUserDeposit {
        uint256 globalDepositAmount;
        uint256 globalLockLpAmount;
        uint256 globalLpAmount;
        int256 globalRewardDebt;
    }

    function init(address _admin, INftHandler _nftHandler, CapConfig memory _depositCapPerWallet) external;
    function enable() external;
    function disable() external;
    function isMaxUserGlobalDeposit(address _user) external view returns (bool);
    function updateNftBoost(address user) external;
    function nftHandler() external view returns (INftHandler);
    function magicTotalDeposits() external view returns (uint256);
}

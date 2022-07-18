// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./INftHandler.sol";

interface IHarvester {
    struct UserInfo {
        uint256 originalDepositAmount;
        uint256 depositAmount;
        uint256 lockLpAmount;
        uint256 lockedUntil;
        uint256 vestingLastUpdate;
        uint256 lock;
    }

    struct CapConfig {
        address parts;
        uint256 partsTokenId;
        uint256 capPerPart;
    }

    struct GlobalUserDeposit {
        uint256 globalDepositAmount;
        uint256 globalLockLpAmount;
        uint256 globalLpAmount;
        int256 globalRewardDebt;
    }

    struct Timelock {
        uint256 boost;
        uint256 timelock;
        uint256 vesting;
        bool enabled;
    }

    function init(address _admin, INftHandler _nftHandler, CapConfig memory _depositCapPerWallet) external;
    function disabled() external view returns (bool);
    function enable() external;
    function disable() external;
    function isMaxUserGlobalDeposit(address _user) external view returns (bool);
    function updateNftBoost(address user) external returns (bool);
    function nftHandler() external view returns (INftHandler);
    function magicTotalDeposits() external view returns (uint256);
}

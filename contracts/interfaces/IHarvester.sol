// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./INftHandler.sol";

interface IHarvester {
    function isMaxUserGlobalDeposit(address _user) external view returns (bool);
    function updateNftBoost(address user) external;
    function nftHandler() external view returns (INftHandler);
    function magicTotalDeposits() external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IHarvester {
    function updateNftBoost(address user, uint256 boost) external;
}

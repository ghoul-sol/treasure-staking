// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import '../interfaces/INftHandler.sol';
import './Harvester.sol';
import './NftHandler.sol';

contract HarvesterFactory is AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant HARVESTER_FACTORY_ADMIN_ROLE = keccak256("HARVESTER_FACTORY_ADMIN_ROLE");

    EnumerableSet.AddressSet private harvesters;

    /// @dev Magic token addr
    IERC20 public magic;
    IMiddleman public middleman;

    event HarvesterDeployed(Harvester harvester, NftHandler nftHandler);

    constructor(address _admin, IERC20 _magic, IMiddleman _middleman) {
        magic = _magic;
        middleman = _middleman;

        _setRoleAdmin(HARVESTER_FACTORY_ADMIN_ROLE, HARVESTER_FACTORY_ADMIN_ROLE);
        _grantRole(HARVESTER_FACTORY_ADMIN_ROLE, _admin);
    }

    function getAllHarvesters() external view returns (address[] memory) {
        return harvesters.values();
    }

    function getAllHarvestersLength() external view returns (uint256) {
        return harvesters.length();
    }

    function deployHarvester(address _admin) external onlyRole(HARVESTER_FACTORY_ADMIN_ROLE) {
        NftHandler nftHandler = new NftHandler(_admin);
        Harvester harvester = new Harvester(_admin, INftHandler(address(nftHandler)));

        require(harvesters.add(address(harvester)), "Harvester address already exists");

        emit HarvesterDeployed(harvester, nftHandler);
    }

    function enableHarvester(Harvester _harvester) external onlyRole(HARVESTER_FACTORY_ADMIN_ROLE) {
        _harvester.enable();
    }

    function disableHarvester(Harvester _harvester) external onlyRole(HARVESTER_FACTORY_ADMIN_ROLE) {
        _harvester.disable();
    }

    // ADMIN

    function setMagicToken(IERC20 _magic) external onlyRole(HARVESTER_FACTORY_ADMIN_ROLE) {
        magic = _magic;
    }

    function setMiddleman(IMiddleman _middleman) external onlyRole(HARVESTER_FACTORY_ADMIN_ROLE) {
        middleman = _middleman;
    }

}

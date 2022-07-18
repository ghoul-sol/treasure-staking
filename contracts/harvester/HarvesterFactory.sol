// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './interfaces/INftHandler.sol';
import './interfaces/IHarvester.sol';
import './interfaces/IMiddleman.sol';

contract HarvesterFactory is AccessControlEnumerableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev master admin, manages other roles and can change core config
    bytes32 public constant HF_ADMIN = keccak256("HF_ADMIN");
    /// @dev can deploy and enable/disable harvesters
    bytes32 public constant HF_DEPLOYER = keccak256("HF_DEPLOYER");
    /// @dev can upgrade proxy implementation for harvester and nftHandler
    bytes32 public constant HF_BEACON_ADMIN = keccak256("HF_BEACON_ADMIN");

    UpgradeableBeacon public nftHandlerBeacon;
    UpgradeableBeacon public harvesterBeacon;

    EnumerableSet.AddressSet private harvesters;

    /// @dev Magic token addr
    IERC20 public magic;
    IMiddleman public middleman;

    event HarvesterDeployed(address harvester, address nftHandler);
    event Magic(IERC20 magic);
    event Middleman(IMiddleman middleman);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function init(
        IERC20 _magic,
        IMiddleman _middleman,
        address _admin,
        address _harvesterImpl,
        address _nftHandlerImpl
    ) external initializer {
        __AccessControlEnumerable_init();

        magic = _magic;
        emit Magic(_magic);

        middleman = _middleman;
        emit Middleman(_middleman);

        _setRoleAdmin(HF_ADMIN, HF_ADMIN);
        _grantRole(HF_ADMIN, _admin);

        _setRoleAdmin(HF_DEPLOYER, HF_ADMIN);
        _grantRole(HF_DEPLOYER, _admin);

        _setRoleAdmin(HF_BEACON_ADMIN, HF_ADMIN);
        _grantRole(HF_BEACON_ADMIN, _admin);

        harvesterBeacon = new UpgradeableBeacon(_harvesterImpl);
        nftHandlerBeacon = new UpgradeableBeacon(_nftHandlerImpl);
    }

    function getHarvester(uint256 _index) external view returns (address) {
        if (harvesters.length() == 0) {
            return address(0);
        } else {
            return harvesters.at(_index);
        }
    }

    function getAllHarvesters() external view returns (address[] memory) {
        return harvesters.values();
    }

    function getAllHarvestersLength() external view returns (uint256) {
        return harvesters.length();
    }

    function deployHarvester(
        address _admin,
        IHarvester.CapConfig memory _depositCapPerWallet,
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        INftHandler.NftConfig[] memory _nftConfigs
    ) external onlyRole(HF_DEPLOYER) {
        address nftHandler = address(new BeaconProxy(address(nftHandlerBeacon), bytes("")));

        for (uint256 i = 0; i < _nfts.length; i++) {
            _nftConfigs[i].stakingRules.setNftHandler(nftHandler);
        }

        bytes memory harvesterData = abi.encodeCall(IHarvester.init, (_admin, INftHandler(nftHandler), _depositCapPerWallet));
        address harvester = address(new BeaconProxy(address(harvesterBeacon), harvesterData));

        require(harvesters.add(harvester), "Harvester address already exists");

        emit HarvesterDeployed(harvester, nftHandler);

        INftHandler(nftHandler).init(_admin, harvester, _nfts, _tokenIds, _nftConfigs);
    }

    function enableHarvester(IHarvester _harvester) external onlyRole(HF_DEPLOYER) {
        _harvester.enable();
    }

    function disableHarvester(IHarvester _harvester) external onlyRole(HF_DEPLOYER) {
        _harvester.disable();
    }

    // ADMIN

    function setMagicToken(IERC20 _magic) external onlyRole(HF_ADMIN) {
        magic = _magic;
        emit Magic(_magic);
    }

    function setMiddleman(IMiddleman _middleman) external onlyRole(HF_ADMIN) {
        middleman = _middleman;
        emit Middleman(_middleman);
    }

    /// @dev Upgrades the harvester beacon to a new implementation.
    function upgradeHarvesterTo(address _newImplementation) external onlyRole(HF_BEACON_ADMIN) {
        harvesterBeacon.upgradeTo(_newImplementation);
    }

    /// @dev Upgrades the nft handler beacon to a new implementation.
    function upgradeNftHandlerTo(address _newImplementation) external onlyRole(HF_BEACON_ADMIN) {
        nftHandlerBeacon.upgradeTo(_newImplementation);
    }
}

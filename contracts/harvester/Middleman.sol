// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './interfaces/IHarvesterFactory.sol';
import './interfaces/IHarvester.sol';
import '../interfaces/IMasterOfCoin.sol';

import './lib/Constant.sol';

contract Middleman is AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct RewardsBalance {
        uint256 unpaid;
        uint256 paid;
    }

    bytes32 public constant MIDDLEMAN_ADMIN = keccak256("MIDDLEMAN_ADMIN");

    /// @dev Magic token addr
    IERC20 public corruptionToken;
    IHarvesterFactory public harvesterFactory;
    IMasterOfCoin public masterOfCoin;
    address public atlasMine;
    uint256 public atlasMineBoost;

    uint256 public lastRewardTimestamp;

    mapping(address => RewardsBalance) public rewardsBalance;

    uint256[][] public corruptionNegativeBoostMatrix;

    EnumerableSet.AddressSet private excludedAddresses;

    event RewardsPaid(address indexed stream, uint256 rewardsPaid, uint256 rewardsPaidInTotal);
    event CorruptionToken(IERC20 corruptionToken);
    event HarvesterFactory(IHarvesterFactory harvesterFactory);
    event AtlasMine(address atlasMine);
    event MasterOfCoin(IMasterOfCoin masterOfCoin);
    event CorruptionNegativeBoostMatrix(uint256[][] _corruptionNegativeBoostMatrix);

    modifier runIfNeeded {
        if (block.timestamp > lastRewardTimestamp) {
            lastRewardTimestamp = block.timestamp;
            _;
        }
    }

    constructor(
        address _admin,
        IMasterOfCoin _masterOfCoin,
        IHarvesterFactory _harvesterFactory,
        address _atlasMine,
        IERC20 _corruptionToken
    ) {
        _setRoleAdmin(MIDDLEMAN_ADMIN, MIDDLEMAN_ADMIN);
        _grantRole(MIDDLEMAN_ADMIN, _admin);

        masterOfCoin = _masterOfCoin;
        emit MasterOfCoin(_masterOfCoin);

        harvesterFactory = _harvesterFactory;
        emit HarvesterFactory(_harvesterFactory);

        atlasMine = _atlasMine;
        emit AtlasMine(_atlasMine);

        corruptionToken = _corruptionToken;
        emit CorruptionToken(_corruptionToken);

        corruptionNegativeBoostMatrix = [
            [60_000e18, 4e17],
            [50_000e18, 5e17],
            [40_000e18, 6e17],
            [30_000e18, 7e17],
            [20_000e18, 8e17],
            [10_000e18, 9e17]
        ];
        emit CorruptionNegativeBoostMatrix(corruptionNegativeBoostMatrix);
    }

    function distributeRewards() public runIfNeeded {
        uint256 distributedRewards = masterOfCoin.requestRewards();

        address[] memory allHarvesters = harvesterFactory.getAllHarvesters();
        uint256[] memory harvesterShare = new uint256[](allHarvesters.length);
        uint256 totalShare;

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            harvesterShare[i] = getHarvesterEmissionsShare(allHarvesters[i]);
            totalShare += harvesterShare[i];
        }

        if (atlasMine != address(0)) {
            totalShare += atlasMineBoost;
            rewardsBalance[atlasMine].unpaid += distributedRewards * atlasMineBoost / totalShare;
        }

        for (uint256 i = 0; i < harvesterShare.length; i++) {
            rewardsBalance[allHarvesters[i]].unpaid += distributedRewards * harvesterShare[i] / totalShare;
        }
    }

    function requestRewards() public returns (uint256 rewardsPaid) {
        distributeRewards();

        address harvester = msg.sender;

        rewardsPaid = rewardsBalance[harvester].unpaid;

        if (rewardsPaid == 0) {
            return 0;
        }

        rewardsBalance[harvester].unpaid = 0;
        rewardsBalance[harvester].paid += rewardsPaid;

        harvesterFactory.magic().safeTransfer(harvester, rewardsPaid);
        emit RewardsPaid(harvester, rewardsPaid, rewardsBalance[harvester].paid);
    }

    function getHarvesterEmissionsShare(address _harvester) public view returns (uint256) {
        uint256 harvesterTotalBoost = IHarvester(_harvester).nftHandler().getHarvesterTotalBoost();
        uint256 utilBoost = getUtilizationBoost(_harvester);
        uint256 corruptionNegativeBoost = getCorruptionNegativeBoost();

        return harvesterTotalBoost * utilBoost / Constant.ONE * corruptionNegativeBoost / Constant.ONE;
    }

    function getCorruptionNegativeBoost() public view returns (uint256 negBoost) {
        negBoost = Constant.ONE;

        uint256 balance = corruptionToken.balanceOf(address(this));

        for (uint256 i = 0; i < corruptionNegativeBoostMatrix.length; i++) {
            uint256 balanceThreshold = corruptionNegativeBoostMatrix[i][0];

            if (balance > balanceThreshold) {
                negBoost = corruptionNegativeBoostMatrix[i][1];
                break;
            }
        }
    }

    function getUtilizationBoost(address _harvester) public view returns (uint256 utilBoost) {
        uint256 util = getUtilization(_harvester);

        if (util < 3e17) {
            // if utilization < 30%, no emissions
            utilBoost = 0;
        } else if (util < 40e16) {
            // if 30% < utilization < 40%, 50% emissions
            utilBoost = 50e16;
        } else if (util < 50e16) {
            // if 40% < utilization < 50%, 60% emissions
            utilBoost = 60e16;
        } else if (util < 60e16) {
            // if 50% < utilization < 60%, 80% emissions
            utilBoost = 80e16;
        } else {
            // 100% emissions above 60% utilization
            utilBoost = 100e16;
        }
    }

    function getUtilization(address _harvester) public view returns (uint256 util) {
        IERC20 magic = harvesterFactory.magic();
        uint256 circulatingSupply = magic.totalSupply();
        uint256 magicTotalDeposits = IHarvester(_harvester).magicTotalDeposits();

        uint256 len = excludedAddresses.length();
        for (uint256 i = 0; i < len; i++) {
            circulatingSupply -= magic.balanceOf(excludedAddresses.at(i));
        }

        uint256 rewardsAmount = magic.balanceOf(_harvester) - magicTotalDeposits;
        circulatingSupply -= rewardsAmount;
        if (circulatingSupply != 0) {
            util = magicTotalDeposits * Constant.ONE / circulatingSupply;
        }
    }

    function getExcludedAddresses() public view virtual returns (address[] memory) {
        return excludedAddresses.values();
    }

    // ADMIN
    function setHarvesterFactory(IHarvesterFactory _harvesterFactory) external onlyRole(MIDDLEMAN_ADMIN) {
        harvesterFactory = _harvesterFactory;
        emit HarvesterFactory(_harvesterFactory);
    }

    function setMasterOfCoin(IMasterOfCoin _masterOfCoin) external onlyRole(MIDDLEMAN_ADMIN) {
        masterOfCoin = _masterOfCoin;
        emit MasterOfCoin(_masterOfCoin);
    }

    function setCorruptionNegativeBoostMatrix(uint256[][] memory _corruptionNegativeBoostMatrix) external onlyRole(MIDDLEMAN_ADMIN) {
        corruptionNegativeBoostMatrix = _corruptionNegativeBoostMatrix;
        emit CorruptionNegativeBoostMatrix(_corruptionNegativeBoostMatrix);
    }

    function addExcludedAddress(address _exclude) external onlyRole(MIDDLEMAN_ADMIN) {
        require(excludedAddresses.add(_exclude), "Address already excluded");
    }

    function removeExcludedAddress(address _excluded) external onlyRole(MIDDLEMAN_ADMIN) {
        require(excludedAddresses.remove(_excluded), "Address is not excluded");
    }
}

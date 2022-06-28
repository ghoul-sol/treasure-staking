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
    event AtlasMineBoost(uint256 atlasMineBoost);
    event AddExcludedAddress(address addr);
    event RemoveExcludedAddress(address addr);

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
        uint256 _atlasMineBoost,
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

        atlasMineBoost = _atlasMineBoost;
        emit AtlasMineBoost(_atlasMineBoost);

        corruptionToken = _corruptionToken;
        emit CorruptionToken(_corruptionToken);

        corruptionNegativeBoostMatrix = [
            [600_000e18, 0.4e18],
            [500_000e18, 0.5e18],
            [400_000e18, 0.6e18],
            [300_000e18, 0.7e18],
            [200_000e18, 0.8e18],
            [100_000e18, 0.9e18]
        ];
        emit CorruptionNegativeBoostMatrix(corruptionNegativeBoostMatrix);
    }

    /// @dev Returns share in mining power for all harvesters. To get percentage of mining power
    ///      for given harvester do:
    ///      `harvesterShare[i] / totalShare`, where `i` is index of harvester address in `allHarvesters`
    ///      array.
    /// @param _targetHarvester optional parameter, you can safely use `address(0)`. If you are looking
    ///        for specific harvester, provide its address as param and `targetIndex` will return index
    ///        of harvester in question in `allHarvesters` array.
    /// @return allHarvesters array of all harvesters
    /// @return harvesterShare share in mining power for each harvester in `allHarvesters` array
    /// @return totalShare sum of all shares (includes `atlasMineBoost` if AtlasMine is setup)
    /// @return targetIndex index of `_targetHarvester` in `allHarvesters` array
    function getHarvesterShares(address _targetHarvester) public view returns (
        address[] memory allHarvesters,
        uint256[] memory harvesterShare,
        uint256 totalShare,
        uint256 targetIndex
    ) {
        allHarvesters = harvesterFactory.getAllHarvesters();
        harvesterShare = new uint256[](allHarvesters.length);

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            harvesterShare[i] = getHarvesterEmissionsShare(allHarvesters[i]);
            totalShare += harvesterShare[i];

            if (allHarvesters[i] == _targetHarvester) {
                targetIndex = i;
            }
        }

        if (atlasMine != address(0) && atlasMineBoost != 0) {
            totalShare += atlasMineBoost;
        }
    }

    function getPendingRewards(address _harvester) public view returns (uint256) {
        uint256 pendingRewards = masterOfCoin.getPendingRewards(address(this));

        (
            address[] memory allHarvesters,
            uint256[] memory harvesterShare,
            uint256 totalShare,
            uint256 targetIndex
        ) = getHarvesterShares(_harvester);

        uint256 unpaidRewards = rewardsBalance[allHarvesters[targetIndex]].unpaid;
        return unpaidRewards + pendingRewards * harvesterShare[targetIndex] / totalShare;
    }

    function getHarvesterEmissionsShare(address _harvester) public view returns (uint256) {
        uint256 harvesterTotalBoost = IHarvester(_harvester).nftHandler().getHarvesterTotalBoost();
        uint256 utilBoost = getUtilizationBoost(_harvester);
        uint256 corruptionNegativeBoost = getCorruptionNegativeBoost(_harvester);

        return harvesterTotalBoost * utilBoost / Constant.ONE * corruptionNegativeBoost / Constant.ONE;
    }

    function getCorruptionNegativeBoost(address _harvester) public view returns (uint256 negBoost) {
        negBoost = Constant.ONE;

        uint256 balance = corruptionToken.balanceOf(_harvester);

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

        if (util < 0.3e18) {
            // if utilization < 30%, no emissions
            utilBoost = 0;
        } else if (util < 0.4e18) {
            // if 30% < utilization < 40%, 50% emissions
            utilBoost = 0.5e18;
        } else if (util < 0.5e18) {
            // if 40% < utilization < 50%, 60% emissions
            utilBoost = 0.6e18;
        } else if (util < 0.6e18) {
            // if 50% < utilization < 60%, 70% emissions
            utilBoost = 0.7e18;
        } else if (util < 0.7e18) {
            // if 60% < utilization < 70%, 80% emissions
            utilBoost = 0.8e18;
        } else if (util < 0.8e18) {
            // if 70% < utilization < 80%, 90% emissions
            utilBoost = 0.9e18;
        } else {
            // 100% emissions above 80% utilization
            utilBoost = 1e18;
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

    function getCorruptionNegativeBoostMatrix() public view returns (uint256[][] memory) {
        return corruptionNegativeBoostMatrix;
    }

    function distributeRewards() public runIfNeeded {
        uint256 distributedRewards = masterOfCoin.requestRewards();

        (
            address[] memory allHarvesters,
            uint256[] memory harvesterShare,
            uint256 totalShare,
        ) = getHarvesterShares(address(0));

        if (atlasMine != address(0) && atlasMineBoost != 0) {
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

    function setAtlasMineBoost(uint256 _atlasMineBoost) external onlyRole(MIDDLEMAN_ADMIN) {
        atlasMineBoost = _atlasMineBoost;
        emit AtlasMineBoost(_atlasMineBoost);
    }

    function addExcludedAddress(address _exclude) external onlyRole(MIDDLEMAN_ADMIN) {
        require(excludedAddresses.add(_exclude), "Address already excluded");
        emit AddExcludedAddress(_exclude);
    }

    function removeExcludedAddress(address _excluded) external onlyRole(MIDDLEMAN_ADMIN) {
        require(excludedAddresses.remove(_excluded), "Address is not excluded");
        emit RemoveExcludedAddress(_excluded);
    }
}

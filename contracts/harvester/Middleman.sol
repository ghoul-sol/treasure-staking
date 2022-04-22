// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../interfaces/IHarvesterFactory.sol';
import '../interfaces/IHarvester.sol';
import '../interfaces/IMasterOfCoin.sol';
import '../interfaces/IAtlasMine.sol';

import './lib/Constant.sol';

contract Middleman is AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct RewardsBalance {
        uint256 unpaid;
        uint256 paid;
    }

    bytes32 public constant MIDDLEMAN_ADMIN_ROLE = keccak256("MIDDLEMAN_ADMIN_ROLE");

    /// @dev Magic token addr
    IERC20 public magic;
    IERC20 public corruptionToken;
    IHarvesterFactory public harvesterFactory;
    IMasterOfCoin public masterOfCoin;
    IAtlasMine public atlasMine;

    uint256 public lastRewardTimestamp;

    mapping(address => RewardsBalance) public rewardsBalance;

    uint256[][] public corruptionNegativeBoostMatrix;

    event RewardsPaid(address indexed stream, uint256 rewardsPaid, uint256 rewardsPaidInTotal);
    event MagicTokenUpdate(IERC20 magic);
    event CorruptionTokenUpdate(IERC20 corruptionToken);
    event HarvesterFactoryUpdate(IHarvesterFactory magic);
    event AtlasMineUpdate(IAtlasMine atlasMine);
    event MasterOfCoinUpdate(IMasterOfCoin magic);
    event CorruptionNegativeBoostMatrixUpdate(uint256[][] _corruptionNegativeBoostMatrix);

    modifier runIfNeeded {
        if (block.timestamp > lastRewardTimestamp) {
            lastRewardTimestamp = block.timestamp;
            _;
        }
    }

    constructor(
        address _admin,
        IERC20 _magic,
        IMasterOfCoin _masterOfCoin,
        IHarvesterFactory _harvesterFactory,
        IAtlasMine _atlasMine,
        IERC20 _corruptionToken
    ) {
        _setRoleAdmin(MIDDLEMAN_ADMIN_ROLE, MIDDLEMAN_ADMIN_ROLE);
        _grantRole(MIDDLEMAN_ADMIN_ROLE, _admin);

        magic = _magic;
        emit MagicTokenUpdate(_magic);

        masterOfCoin = _masterOfCoin;
        emit MasterOfCoinUpdate(_masterOfCoin);

        harvesterFactory = _harvesterFactory;
        emit HarvesterFactoryUpdate(_harvesterFactory);

        atlasMine = _atlasMine;
        emit AtlasMineUpdate(_atlasMine);

        corruptionToken = _corruptionToken;
        emit CorruptionTokenUpdate(_corruptionToken);

        corruptionNegativeBoostMatrix = [
            [60_000e18, 4e17],
            [50_000e18, 5e17],
            [40_000e18, 6e17],
            [30_000e18, 7e17],
            [20_000e18, 8e17],
            [10_000e18, 9e17]
        ];
        emit CorruptionNegativeBoostMatrixUpdate(corruptionNegativeBoostMatrix);
    }

    function distributeRewards() public runIfNeeded {
        uint256 distributedRewards = masterOfCoin.requestRewards();

        address[] memory allHarvesters = harvesterFactory.getAllHarvesters();
        uint256[] memory harvesterBoosts = new uint256[](allHarvesters.length);
        uint256 totalBoost;

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            harvesterBoosts[i] = getHarvesterTotalBoost(allHarvesters[i]);
            totalBoost += harvesterBoosts[i];
        }

        for (uint256 i = 0; i < harvesterBoosts.length; i++) {
            rewardsBalance[allHarvesters[i]].unpaid += distributedRewards * harvesterBoosts[i] / totalBoost;
        }
    }

    function requestRewards() public virtual returns (uint256 rewardsPaid) {
        distributeRewards();

        address harvester = msg.sender;

        rewardsPaid = rewardsBalance[harvester].unpaid;

        if (rewardsPaid == 0) {
            return 0;
        }

        rewardsBalance[harvester].unpaid = 0;
        rewardsBalance[harvester].paid += rewardsPaid;

        magic.safeTransfer(harvester, rewardsPaid);
        emit RewardsPaid(harvester, rewardsPaid, rewardsBalance[harvester].paid);
    }

    function getHarvesterTotalBoost(address _harvester) public view returns (uint256) {
        uint256 harvesterTotalBoost = IHarvester(_harvester).nftHandler().getHarvesterTotalBoost();
        uint256 corruptionNegativeBoost = getCorruptionNegativeBoost();

        return harvesterTotalBoost * corruptionNegativeBoost / Constant.ONE;
    }

    function getCorruptionNegativeBoost() public view returns (uint256 negBoost) {
        negBoost = Constant.ONE;

        uint256 balance = corruptionToken.balanceOf(address(this));

        for (uint256 i = 0; i < corruptionNegativeBoostMatrix.length; i++) {
            uint256 balanceThreshold = corruptionNegativeBoostMatrix[i][0];

            if (balance > balanceThreshold) {
                negBoost = corruptionNegativeBoostMatrix[i][1];
            }
        }
    }

    // ADMIN

    function setMagicToken(IERC20 _magic) external onlyRole(MIDDLEMAN_ADMIN_ROLE) {
        magic = _magic;
        emit MagicTokenUpdate(_magic);
    }

    function setHarvesterFactory(IHarvesterFactory _harvesterFactory) external onlyRole(MIDDLEMAN_ADMIN_ROLE) {
        harvesterFactory = _harvesterFactory;
        emit HarvesterFactoryUpdate(_harvesterFactory);
    }

    function setMasterOfCoin(IMasterOfCoin _masterOfCoin) external onlyRole(MIDDLEMAN_ADMIN_ROLE) {
        masterOfCoin = _masterOfCoin;
        emit MasterOfCoinUpdate(_masterOfCoin);
    }

    function setCorruptionNegativeBoostMatrix(uint256[][] memory _corruptionNegativeBoostMatrix) external onlyRole(MIDDLEMAN_ADMIN_ROLE) {
        corruptionNegativeBoostMatrix = _corruptionNegativeBoostMatrix;
        emit CorruptionNegativeBoostMatrixUpdate(_corruptionNegativeBoostMatrix);
    }
}

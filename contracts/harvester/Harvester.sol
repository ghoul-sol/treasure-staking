// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';

import './interfaces/INftHandler.sol';
import './interfaces/IPartsStakingRules.sol';
import './interfaces/IHarvesterFactory.sol';

contract Harvester is IHarvester, Initializable, AccessControlEnumerableUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;

    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    bytes32 public constant HARVESTER_ADMIN = keccak256("HARVESTER_ADMIN");

    uint256 public constant DAY = 1 days;
    uint256 public constant ONE_WEEK = 7 days;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;
    uint256 public constant ONE_MONTH = 30 days;
    uint256 public constant THREE_MONTHS = ONE_MONTH * 3;
    uint256 public constant SIX_MONTHS = ONE_MONTH * 6;
    uint256 public constant TWELVE_MONTHS = 365 days;
    uint256 public constant ONE = 1e18;

    IHarvesterFactory public factory;

    INftHandler public nftHandler;

    bool public unlockAll;
    bool public disabled;

    uint256 public totalRewardsEarned;
    uint256 public accMagicPerShare;
    uint256 public totalLpToken;
    uint256 public magicTotalDeposits;

    /// @notice amount of MAGIC that can be deposited
    uint256 public totalDepositCap;

    CapConfig public depositCapPerWallet;

    /// @notice user => depositId => UserInfo
    mapping (address => mapping (uint256 => UserInfo)) public userInfo;
    /// @notice user => GlobalUserDeposit
    mapping (address => GlobalUserDeposit) public getUserGlobalDeposit;
    /// @notice user => depositId[]
    mapping (address => EnumerableSet.UintSet) private allUserDepositIds;
    /// @notice user => deposit index
    mapping (address => uint256) public currentId;

    event Deposit(address indexed user, uint256 indexed index, uint256 amount, Lock lock);
    event Withdraw(address indexed user, uint256 indexed index, uint256 amount);
    event UndistributedRewardsWithdraw(address indexed to, uint256 amount);
    event Harvest(address indexed user, uint256 amount);
    event LogUpdateRewards(uint256 distributedRewards, uint256 lpSupply, uint256 accMagicPerShare);
    event Enable();
    event Disable();
    event NftHandler(INftHandler nftHandler);
    event DepositCapPerWallet(CapConfig depositCapPerWallet);
    event TotalDepositCap(uint256 totalDepositCap);
    event UnlockAll(bool value);

    modifier updateRewards() {
        uint256 lpSupply = totalLpToken;
        if (lpSupply > 0 && !disabled) {
            uint256 distributedRewards = factory.middleman().requestRewards();
            totalRewardsEarned += distributedRewards;
            accMagicPerShare += distributedRewards * ONE / lpSupply;
            emit LogUpdateRewards(distributedRewards, lpSupply, accMagicPerShare);
        }

        _;
    }

    modifier checkDepositCaps() {
        _;

        if (isMaxUserGlobalDeposit(msg.sender)) {
            revert("MaxUserGlobalDeposit()");
        }

        if (magicTotalDeposits > totalDepositCap) revert("MaxTotalDeposit()");
    }

    modifier whenEnabled() {
        if (disabled) revert("Disabled()");

        _;
    }

    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert("OnlyFactory()");

        _;
    }

    function init(
        address _admin,
        INftHandler _nftHandler,
        CapConfig memory _depositCapPerWallet
    ) external initializer {
        totalDepositCap = 10_000_000e18;
        emit TotalDepositCap(totalDepositCap);

        factory = IHarvesterFactory(msg.sender);

        _setRoleAdmin(HARVESTER_ADMIN, HARVESTER_ADMIN);
        _grantRole(HARVESTER_ADMIN, _admin);

        nftHandler = _nftHandler;
        emit NftHandler(_nftHandler);

        depositCapPerWallet = _depositCapPerWallet;
        emit DepositCapPerWallet(_depositCapPerWallet);

        __AccessControlEnumerable_init();
    }

    function getUserBoost(address _user) external view returns (uint256) {
        return nftHandler.getUserBoost(_user);
    }

    function getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) external view returns (uint256) {
        return nftHandler.getNftBoost(_user, _nft, _tokenId, _amount);
    }

    function getAllUserDepositIds(address _user) external view returns (uint256[] memory) {
        return allUserDepositIds[_user].values();
    }

    function getAllUserDepositIdsLength(address _user) external view returns (uint256) {
        return allUserDepositIds[_user].length();
    }

    /// @notice Gets amount of MAGIC that a single wallet can deposit
    function getUserDepositCap(address _user) public view returns (uint256 cap) {
        address stakingRules = nftHandler.getStakingRules(depositCapPerWallet.parts);

        if (stakingRules != address(0)) {
            uint256 amountStaked = IPartsStakingRules(stakingRules).getAmountStaked(_user);
            cap = amountStaked * depositCapPerWallet.capPerPart;
        }
    }

    function getLockBoost(Lock _lock) public pure returns (uint256 boost, uint256 timelock) {
        if (_lock == Lock.twoWeeks) {
            // 10%
            return (0.1e18, TWO_WEEKS);
        } else if (_lock == Lock.oneMonth) {
            // 25%
            return (0.25e18, ONE_MONTH);
        } else if (_lock == Lock.threeMonths) {
            // 80%
            return (0.8e18, THREE_MONTHS);
        } else if (_lock == Lock.sixMonths) {
            // 180%
            return (1.8e18, SIX_MONTHS);
        } else if (_lock == Lock.twelveMonths) {
            // 400%
            return (4e18, TWELVE_MONTHS);
        } else {
            revert("Invalid lock value");
        }
    }

    function getVestingTime(Lock _lock) public pure returns (uint256 vestingTime) {
        if (_lock == Lock.twoWeeks) {
            vestingTime = 0;
        } else if (_lock == Lock.oneMonth) {
            vestingTime = 7 days;
        } else if (_lock == Lock.threeMonths) {
            vestingTime = 14 days;
        } else if (_lock == Lock.sixMonths) {
            vestingTime = 30 days;
        } else if (_lock == Lock.twelveMonths) {
            vestingTime = 45 days;
        }
    }

    function calcualteVestedPrincipal(address _user, uint256 _depositId)
        public
        view
        returns (uint256 amount)
    {
        UserInfo storage user = userInfo[_user][_depositId];
        Lock _lock = user.lock;
        uint256 originalDepositAmount = user.originalDepositAmount;

        uint256 vestingEnd = user.lockedUntil + getVestingTime(_lock);
        uint256 vestingBegin = user.lockedUntil;

        if (block.timestamp >= vestingEnd || unlockAll) {
            amount = user.depositAmount;
        } else if (block.timestamp > vestingBegin) {
            uint256 amountVested = originalDepositAmount * (block.timestamp - vestingBegin) / (vestingEnd - vestingBegin);
            uint256 amountWithdrawn = originalDepositAmount - user.depositAmount;
            if (amountWithdrawn < amountVested) {
                amount = amountVested - amountWithdrawn;
            }
        }
    }

    function isMaxUserGlobalDeposit(address _user) public view returns (bool) {
        return getUserGlobalDeposit[_user].globalDepositAmount > getUserDepositCap(_user);
    }

    function pendingRewardsAll(address _user) external view returns (uint256 pending) {
        GlobalUserDeposit storage userGlobalDeposit = getUserGlobalDeposit[_user];
        uint256 _accMagicPerShare = accMagicPerShare;
        uint256 lpSupply = totalLpToken;

        // if harvester is disabled, only account for rewards that were already sent
        if (!disabled && lpSupply > 0) {
            uint256 pendingRewards = factory.middleman().getPendingRewards(address(this));
            _accMagicPerShare += pendingRewards * ONE / lpSupply;
        }

        int256 accumulatedMagic = (userGlobalDeposit.globalLpAmount * _accMagicPerShare / ONE).toInt256();
        pending = (accumulatedMagic - userGlobalDeposit.globalRewardDebt).toUint256();
    }

    function updateNftBoost(address _user) external returns (bool) {
        _recalculateGlobalLp(_user, 0, 0);

        return true;
    }

    function enable() external onlyFactory {
        disabled = false;
        emit Enable();
    }

    function disable() external onlyFactory {
        disabled = true;
        emit Disable();
    }

    function deposit(uint256 _amount, Lock _lock) external updateRewards checkDepositCaps whenEnabled {
        (UserInfo storage user, uint256 depositId) = _addDeposit(msg.sender);

        (uint256 lockBoost, uint256 timelock) = getLockBoost(_lock);
        uint256 lockLpAmount = _amount + _amount * lockBoost / ONE;
        magicTotalDeposits += _amount;

        user.originalDepositAmount = _amount;
        user.depositAmount = _amount;
        user.lockLpAmount = lockLpAmount;
        user.lockedUntil = block.timestamp + timelock;
        user.vestingLastUpdate = user.lockedUntil;
        user.lock = _lock;

        _recalculateGlobalLp(msg.sender, _amount.toInt256(), lockLpAmount.toInt256());

        factory.magic().safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, depositId, _amount, _lock);
    }

    function withdrawPosition(uint256 _depositId, uint256 _amount) public updateRewards returns (bool) {
        if (_amount == 0) revert("ZeroAmount()");

        UserInfo storage user = userInfo[msg.sender][_depositId];
        uint256 depositAmount = user.depositAmount;
        if (depositAmount == 0) return false;

        if (_amount > depositAmount) {
            _amount = depositAmount;
        }

        // anyone can withdraw if kill swith was used
        if (!unlockAll) {
            if (block.timestamp < user.lockedUntil) revert("StillLocked()");

            uint256 vestedAmount = _vestedPrincipal(msg.sender, _depositId);
            if (_amount > vestedAmount) {
                _amount = vestedAmount;
            }
        }

        // Effects
        uint256 ratio = _amount * ONE / depositAmount;
        uint256 lockLpAmount = user.lockLpAmount * ratio / ONE;

        magicTotalDeposits -= _amount;

        user.depositAmount -= _amount;
        user.lockLpAmount -= lockLpAmount;

        int256 amountInt = _amount.toInt256();
        int256 lockLpAmountInt = lockLpAmount.toInt256();
        uint256 pendingRewards = _recalculateGlobalLp(msg.sender, -amountInt, -lockLpAmountInt);

        if (user.depositAmount == 0 && user.lockLpAmount == 0 && pendingRewards == 0) {
            _removeDeposit(msg.sender, _depositId);
        }

        // Interactions
        factory.magic().safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _depositId, _amount);

        return true;
    }

    function withdrawAll() public {
        uint256[] memory depositIds = allUserDepositIds[msg.sender].values();
        for (uint256 i = 0; i < depositIds.length; i++) {
            withdrawPosition(depositIds[i], type(uint256).max);
        }
    }

    function harvestAll() public updateRewards {
        GlobalUserDeposit storage userGlobalDeposit = getUserGlobalDeposit[msg.sender];

        int256 accumulatedMagic = (userGlobalDeposit.globalLpAmount * accMagicPerShare / ONE).toInt256();
        uint256 _pendingMagic = (accumulatedMagic - userGlobalDeposit.globalRewardDebt).toUint256();

        // Effects
        userGlobalDeposit.globalRewardDebt = accumulatedMagic;

        IERC20 magic = factory.magic();

        // Interactions
        if (_pendingMagic != 0) {
            magic.safeTransfer(msg.sender, _pendingMagic);
        }

        emit Harvest(msg.sender, _pendingMagic);

        if (magic.balanceOf(address(this)) < magicTotalDeposits) revert("RunOnBank()");
    }

    function withdrawAndHarvestPosition(uint256 _depositId, uint256 _amount) public {
        harvestAll();
        withdrawPosition(_depositId, _amount);
    }

    function withdrawAndHarvestAll() public {
        harvestAll();

        uint256[] memory depositIds = allUserDepositIds[msg.sender].values();
        for (uint256 i = 0; i < depositIds.length; i++) {
            withdrawPosition(depositIds[i], type(uint256).max);
        }
    }

    function _recalculateGlobalLp(address _user, int256 _amount, int256 _lockLpAmount) internal returns (uint256 pendingRewards) {
        GlobalUserDeposit storage userGlobalDeposit = getUserGlobalDeposit[_user];
        uint256 nftBoost = nftHandler.getUserBoost(_user);
        uint256 newGlobalLockLpAmount = (userGlobalDeposit.globalLockLpAmount.toInt256() + _lockLpAmount).toUint256();
        uint256 newGlobalLpAmount = newGlobalLockLpAmount + newGlobalLockLpAmount * nftBoost / ONE;
        int256 globalLpDiff = newGlobalLpAmount.toInt256() - userGlobalDeposit.globalLpAmount.toInt256();

        userGlobalDeposit.globalDepositAmount = (userGlobalDeposit.globalDepositAmount.toInt256() + _amount).toUint256();
        userGlobalDeposit.globalLockLpAmount = newGlobalLockLpAmount;
        userGlobalDeposit.globalLpAmount = newGlobalLpAmount;
        userGlobalDeposit.globalRewardDebt += globalLpDiff * accMagicPerShare.toInt256() / ONE.toInt256();

        totalLpToken = (totalLpToken.toInt256() + globalLpDiff).toUint256();

        int256 accumulatedMagic = (newGlobalLpAmount * accMagicPerShare / ONE).toInt256();
        pendingRewards = (accumulatedMagic - userGlobalDeposit.globalRewardDebt).toUint256();
    }

    function _vestedPrincipal(address _user, uint256 _depositId) internal returns (uint256 amount) {
        amount = calcualteVestedPrincipal(_user, _depositId);
        UserInfo storage user = userInfo[_user][_depositId];
        user.vestingLastUpdate = block.timestamp;
    }

    function _addDeposit(address _user) internal returns (UserInfo storage user, uint256 newDepositId) {
        // start depositId from 1
        newDepositId = ++currentId[_user];
        allUserDepositIds[_user].add(newDepositId);
        user = userInfo[_user][newDepositId];
    }

    function _removeDeposit(address _user, uint256 _depositId) internal {
        if (!allUserDepositIds[_user].remove(_depositId)) revert("DepositDoesNotExists()");
    }

    // ADMIN

    function setNftHandler(INftHandler _nftHandler) external onlyRole(HARVESTER_ADMIN) {
        nftHandler = _nftHandler;
        emit NftHandler(_nftHandler);
    }

    function setDepositCapPerWallet(CapConfig memory _depositCapPerWallet) external onlyRole(HARVESTER_ADMIN) {
        depositCapPerWallet = _depositCapPerWallet;
        emit DepositCapPerWallet(_depositCapPerWallet);
    }

    function setTotalDepositCap(uint256 _totalDepositCap) external onlyRole(HARVESTER_ADMIN) {
        totalDepositCap = _totalDepositCap;
        emit TotalDepositCap(_totalDepositCap);
    }

    /// @notice EMERGENCY ONLY
    function setUnlockAll(bool _value) external onlyRole(HARVESTER_ADMIN) {
        unlockAll = _value;
        emit UnlockAll(_value);
    }
}

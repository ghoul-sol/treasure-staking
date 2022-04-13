// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

import '../interfaces/IMasterOfCoin.sol';
import '../interfaces/INftHandler.sol';
import '../interfaces/IPartsStakingRules.sol';

contract Harvester is AccessControlEnumerable, ERC1155Holder {
    using EnumerableSet for EnumerableSet.UintSet;

    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

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

    bytes32 public constant HARVESTER_ADMIN_ROLE = keccak256("HARVESTER_ADMIN_ROLE");

    uint256 public constant DAY = 1 days;
    uint256 public constant ONE_WEEK = 7 days;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;
    uint256 public constant ONE_MONTH = 30 days;
    uint256 public constant THREE_MONTHS = ONE_MONTH * 3;
    uint256 public constant SIX_MONTHS = ONE_MONTH * 6;
    uint256 public constant TWELVE_MONTHS = 365 days;
    uint256 public constant ONE = 1e18;

    // Magic token addr
    IERC20 public magic;
    IMasterOfCoin public masterOfCoin;
    INftHandler public nftHandler;

    bool public unlockAll;

    uint256 public totalRewardsEarned;
    uint256 public accMagicPerShare;
    uint256 public totalLpToken;
    uint256 public magicTotalDeposits;

    /// @notice amount of MAGIC that can be deposited
    uint256 public totalDepositCap = 10_000_000e18;

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

    modifier updateRewards() {
        uint256 lpSupply = totalLpToken;
        if (lpSupply > 0) {
            uint256 distributedRewards = masterOfCoin.requestRewards();
            totalRewardsEarned += distributedRewards;
            accMagicPerShare += distributedRewards * ONE / lpSupply;
            emit LogUpdateRewards(distributedRewards, lpSupply, accMagicPerShare);
        }

        _;
    }

    modifier checkDepositCaps() {
        _;

        if (getUserGlobalDeposit[msg.sender].globalDepositAmount > getUserDepositCap(msg.sender)) {
            revert("MaxUserGlobalDeposit()");
        }

        if (magicTotalDeposits > totalDepositCap) revert("MaxTotalDeposit()");
    }

    constructor(IERC20 _magic, IMasterOfCoin _masterOfCoin, INftHandler _nftHandler) {
        magic = _magic;
        masterOfCoin = _masterOfCoin;
        nftHandler = _nftHandler;

        _setRoleAdmin(HARVESTER_ADMIN_ROLE, HARVESTER_ADMIN_ROLE);
        _grantRole(HARVESTER_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view

        override(ERC1155Receiver, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function getUserBoost(address _user) external view returns (uint256) {
        return nftHandler.getUserBoost(_user);
    }

    function getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) external view returns (uint256) {
        return nftHandler.getNftBoost(_user, _nft, _tokenId, _amount);
    }

    function updateNftBoost(address _user) external {
        _recalculateGlobalLp(_user, 0, 0);
    }

    function getAllUserDepositIds(address _user) external view returns (uint256[] memory) {
        return allUserDepositIds[_user].values();
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
            return (10e16, TWO_WEEKS);
        } else if (_lock == Lock.oneMonth) {
            // 25%
            return (25e16, ONE_MONTH);
        } else if (_lock == Lock.threeMonths) {
            // 80%
            return (80e16, THREE_MONTHS);
        } else if (_lock == Lock.sixMonths) {
            // 180%
            return (180e16, SIX_MONTHS);
        } else if (_lock == Lock.twelveMonths) {
            // 400%
            return (400e16, TWELVE_MONTHS);
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

    function pendingRewardsAll(address _user) external view returns (uint256 pending) {
        GlobalUserDeposit storage userGlobalDeposit = getUserGlobalDeposit[_user];
        uint256 _accMagicPerShare = accMagicPerShare;
        uint256 lpSupply = totalLpToken;

        uint256 pendingRewards = masterOfCoin.getPendingRewards(address(this));
        _accMagicPerShare += pendingRewards * ONE / lpSupply;

        int256 accumulatedMagic = (userGlobalDeposit.globalLpAmount * _accMagicPerShare / ONE).toInt256();
        pending = (accumulatedMagic - userGlobalDeposit.globalRewardDebt).toUint256();
    }

    function deposit(uint256 _amount, Lock _lock) external updateRewards checkDepositCaps {
        require(allUserDepositIds[msg.sender].length() < 3000, "Max deposits number reached");

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

        magic.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, depositId, _amount, _lock);
    }

    function withdrawPosition(uint256 _depositId, uint256 _amount) public updateRewards returns (bool) {
        UserInfo storage user = userInfo[msg.sender][_depositId];
        uint256 depositAmount = user.depositAmount;
        if (depositAmount == 0) return false;

        if (_amount > depositAmount) {
            _amount = depositAmount;
        }

        // anyone can withdraw if kill swith was used
        if (!unlockAll) {
            require(block.timestamp >= user.lockedUntil, "Position is still locked");
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
        magic.safeTransfer(msg.sender, _amount);

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

        // Interactions
        if (_pendingMagic != 0) {
            magic.safeTransfer(msg.sender, _pendingMagic);
        }

        emit Harvest(msg.sender, _pendingMagic);

        require(magic.balanceOf(address(this)) >= magicTotalDeposits, "Run on banks");
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
        require(allUserDepositIds[_user].remove(_depositId), 'depositId !exists');
    }

    // ADMIN

    function setMagicToken(IERC20 _magic) external onlyRole(HARVESTER_ADMIN_ROLE) {
        magic = _magic;
    }

    function setNftHandler(INftHandler _nftHandler) external onlyRole(HARVESTER_ADMIN_ROLE) {
        nftHandler = _nftHandler;
    }

    function setDepositCapPerWallet(CapConfig memory _depositCapPerWallet) external onlyRole(HARVESTER_ADMIN_ROLE) {
        depositCapPerWallet = _depositCapPerWallet;
    }

    function setTotalDepositCap(uint256 _totalDepositCap) external onlyRole(HARVESTER_ADMIN_ROLE) {
        totalDepositCap = _totalDepositCap;
    }

    /// @notice EMERGENCY ONLY
    function toggleUnlockAll() external onlyRole(HARVESTER_ADMIN_ROLE) updateRewards {
        unlockAll = unlockAll ? false : true;
    }
}

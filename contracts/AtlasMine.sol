// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './interfaces/IMasterOfCoin.sol';

contract AtlasMine is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    using SafeERC20 for ERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    enum Lock { twoWeeks, oneMonth, threeMonths, sixMonths, twelveMonths }

    uint256 public constant DAY = 1 days;
    uint256 public constant ONE_WEEK = 7 days;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;
    uint256 public constant ONE_MONTH = 30 days;
    uint256 public constant THREE_MONTHS = ONE_MONTH * 3;
    uint256 public constant SIX_MONTHS = ONE_MONTH * 6;
    uint256 public constant TWELVE_MONTHS = 365 days;
    uint256 public constant ONE = 1e18;

    // Magic token addr
    ERC20 public immutable magic;
    IMasterOfCoin public immutable masterOfCoin;

    bool public unlockAll;
    uint256 public endTimestamp;

    uint256 public totalRewardsEarned;
    uint256 public totalUndistributedRewards;
    uint256 public accMagicPerShare;
    uint256 public totalLpToken;
    uint256 public magicTotalDeposits;
    uint256 public lastRewardTimestamp;

    EnumerableSet.AddressSet private excludedAddresses;
    EnumerableSet.AddressSet private acceptedNfts;

    struct UserInfo {
        uint256 originalDepositAmount;
        uint256 depositAmount;
        uint256 lpAmount;
        uint256 lockedUntil;
        uint256 vestingLastUpdate;
        int256 rewardDebt;
        Lock lock;
    }

    /// @notice user => depositId => UserInfo
    mapping (address => mapping (uint256 => UserInfo)) public userInfo;
    /// @notice user => depositId[]
    mapping (address => uint256[]) public allUserDepositIds;
    /// @notice user => depositId => index in allUserDepositIds
    mapping (address => mapping(uint256 => uint256)) public depositIdIndex;
    /// @notice user => deposit index array
    mapping (address => uint256) public currentId;


    // /// @notice user => depositId => UserInfo
    // mapping (address => mapping (uint256 => UserInfo)) public userInfo;
    //
    // /// @notice user => depositId[]
    // mapping (address => EnumerableSet.UintSet) private allUserDepositIds;


    // user => nft => tokenIds
    mapping (address => mapping(address => EnumerableSet.UintSet)) private nftStaked;
    // user => nft addresses
    mapping (address => EnumerableSet.AddressSet) private userNfts;
    // user => boost
    mapping (address => uint256) public boosts;

    event Staked(address nft, uint256 tokenId, uint256 currentBoost);
    event Unstaked(address nft, uint256 tokenId, uint256 currentBoost);

    event Deposit(address indexed user, uint256 indexed index, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed index, uint256 amount);
    event UndistributedRewardsWithdraw(address indexed to, uint256 amount);
    event Harvest(address indexed user, uint256 indexed index, uint256 amount);
    event LogUpdateRewards(uint256 distributedRewards, uint256 undistributedRewards, uint256 lpSupply, uint256 accMagicPerShare);

    modifier updateRewards() {
        uint256 lpSupply = totalLpToken;
        if (lpSupply > 0) {
            (uint256 distributedRewards, uint256 undistributedRewards) = getRealMagicReward(masterOfCoin.requestRewards());
            totalRewardsEarned += distributedRewards;
            totalUndistributedRewards += undistributedRewards;
            accMagicPerShare += distributedRewards * ONE / lpSupply;
            emit LogUpdateRewards(distributedRewards, undistributedRewards, lpSupply, accMagicPerShare);
        }
        _;
    }

    constructor(address _magic, address _masterOfCoin) {
        magic = ERC20(_magic);
        masterOfCoin = IMasterOfCoin(_masterOfCoin);
    }

    function getStakedNfts(address _user) external view returns (address[] memory) {
        return userNfts[_user].values();
    }

    function getStakedTokenIds(address _user, address _nft) external view returns (uint256[] memory) {
        return nftStaked[_user][_nft].values();
    }

    function getUserBoost(address _user) external view returns (uint256) {
        return boosts[_user];
    }

    function utilization() public view returns (uint256 util) {
        uint256 circulatingSupply = magic.totalSupply();
        uint256 len = excludedAddresses.length();
        for (uint256 i = 0; i < len; i++) {
            circulatingSupply -= magic.balanceOf(excludedAddresses.at(i));
        }
        uint256 rewardsAmount = magic.balanceOf(address(this)) - magicTotalDeposits;
        circulatingSupply -= rewardsAmount;
        if (circulatingSupply != 0) {
            util = magicTotalDeposits * ONE / circulatingSupply;
        }
    }

    function getRealMagicReward(uint256 _magicReward)
        public
        view
        returns (uint256 distributedRewards, uint256 undistributedRewards)
    {
        uint256 util = utilization();

        if (util < 3e17) {
            distributedRewards = 0;
        } else if (util < 4e17) { // >30%
            // 50%
            distributedRewards = _magicReward * 5 / 10;
        } else if (util < 5e17) { // >40%
            // 60%
            distributedRewards = _magicReward * 6 / 10;
        } else if (util < 6e17) { // >50%
            // 80%
            distributedRewards = _magicReward * 8 / 10;
        } else { // >60%
            // 100%
            distributedRewards = _magicReward;
        }

        undistributedRewards = _magicReward - distributedRewards;
    }

    function getAllUserDepositIds(address _user) public view returns (uint256[] memory) {
        return allUserDepositIds[_user];
    }

    function getExcludedAddresses() public view returns (address[] memory) {
        return excludedAddresses.values();
    }

    function getLockBoost(Lock _lock) public pure returns (uint256 boost, uint256 timelock) {
        if (_lock == Lock.twoWeeks) {
            // 10%
            return (1e17, TWO_WEEKS);
        } else if (_lock == Lock.oneMonth) {
            // 25%
            return (25e16, ONE_MONTH);
        } else if (_lock == Lock.threeMonths) {
            // 80%
            return (8e17, THREE_MONTHS);
        } else if (_lock == Lock.sixMonths) {
            // 180%
            return (18e17, SIX_MONTHS);
        } else if (_lock == Lock.twelveMonths) {
            // 400%
            return (8e17, TWELVE_MONTHS);
        } else {
            revert("Invalid lock value");
        }
    }

    function calcualteVestedPrincipal(address _user, uint256 _depositId) public view returns (uint256 amount) {
        UserInfo storage user = userInfo[_user][_depositId];
        Lock _lock = user.lock;

        uint256 _vestingEnd;
        if (_lock == Lock.twoWeeks) {
            _vestingEnd = user.lockedUntil;
        } else if (_lock == Lock.oneMonth) {
            _vestingEnd = user.lockedUntil + 7 days;
        } else if (_lock == Lock.threeMonths) {
            _vestingEnd = user.lockedUntil + 14 days;
        } else if (_lock == Lock.sixMonths) {
            _vestingEnd = user.lockedUntil + 30 days;
        } else if (_lock == Lock.twelveMonths) {
            _vestingEnd = user.lockedUntil + 45 days;
        }

        uint256 _vestingBegin = user.lockedUntil;
        if (block.timestamp >= _vestingEnd || unlockAll) {
            amount = user.originalDepositAmount;
        } else {
            amount = user.originalDepositAmount * (block.timestamp - user.vestingLastUpdate) / (_vestingEnd - _vestingBegin);
        }
    }

    function pendingRewardsPosition(address _user, uint256 _depositId) public view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user][_depositId];
        uint256 _accMagicPerShare = accMagicPerShare;
        uint256 lpSupply = totalLpToken;

        (uint256 distributedRewards,) = getRealMagicReward(masterOfCoin.getPendingRewards(address(this)));
        _accMagicPerShare += distributedRewards * ONE / lpSupply;

        pending = ((user.lpAmount * _accMagicPerShare / ONE).toInt256() - user.rewardDebt).toUint256();
    }

    function pendingRewardsAll(address _user) external view returns (uint256 pending) {
        uint256 len = allUserDepositIds[_user].length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 depositId = allUserDepositIds[_user][i];
            pending += pendingRewardsPosition(_user, depositId);
        }
    }

    function deposit(uint256 _amount, Lock _lock) public updateRewards {
        (UserInfo storage user, uint256 depositId) = _addDeposit(msg.sender);
        (uint256 lockBoost, uint256 timelock) = getLockBoost(_lock);
        uint256 nftBoost = boosts[msg.sender];
        uint256 lpAmount = _amount + _amount * (lockBoost + nftBoost) / ONE;
        magicTotalDeposits += _amount;
        totalLpToken += lpAmount;

        user.originalDepositAmount = _amount;
        user.depositAmount = _amount;
        user.lpAmount = lpAmount;
        user.lockedUntil = block.timestamp + timelock;
        user.vestingLastUpdate = user.lockedUntil;
        user.rewardDebt = (lpAmount * accMagicPerShare / ONE).toInt256();
        user.lock = _lock;

        magic.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, depositId, _amount);
    }

    function withdrawPosition(uint256 _depositId, uint256 _amount) public updateRewards {
        UserInfo storage user = userInfo[msg.sender][_depositId];
        uint256 depositAmount = user.depositAmount;
        require(depositAmount > 0, "Position does not exists");

        if (_amount > depositAmount) {
            _amount = depositAmount;
        }
        // anyone can withdraw if kill swith was used
        if (!unlockAll) {
            require(block.timestamp >= user.lockedUntil, "Position is still locked");
            require(_vestedPrincipal(msg.sender, _depositId) >= _amount, "Principal not vested");
        }

        // Effects
        uint256 ratio = _amount * ONE / depositAmount;
        uint256 lpAmount = user.lpAmount * ratio / ONE;

        totalLpToken -= lpAmount;
        magicTotalDeposits -= _amount;

        user.depositAmount -= _amount;
        user.lpAmount -= lpAmount;
        user.rewardDebt -= (lpAmount * accMagicPerShare / ONE).toInt256();

        // Interactions
        magic.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _depositId, _amount);
    }

    function withdrawAll() public {
        uint256[] memory depositIds = allUserDepositIds[msg.sender];
        uint256 len = depositIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 depositId = depositIds[i];
            withdrawPosition(depositId, type(uint256).max);
        }
    }

    function harvestPosition(uint256 _depositId) public updateRewards {
        UserInfo storage user = userInfo[msg.sender][_depositId];

        int256 accumulatedMagic = (user.lpAmount * accMagicPerShare / ONE).toInt256();
        uint256 _pendingMagic = (accumulatedMagic - user.rewardDebt).toUint256();

        // Effects
        user.rewardDebt = accumulatedMagic;

        if (user.depositAmount == 0 && user.lpAmount == 0) {
            _removeDeposit(msg.sender, _depositId);
        }

        // Interactions
        if (_pendingMagic != 0) {
            magic.safeTransfer(msg.sender, _pendingMagic);
        }

        emit Harvest(msg.sender, _depositId, _pendingMagic);
    }

    function harvestAll() public {
        uint256[] memory depositIds = allUserDepositIds[msg.sender];
        uint256 len = depositIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 depositId = depositIds[i];
            harvestPosition(depositId);
        }
    }

    function withdrawAndHarvestPosition(uint256 _depositId, uint256 _amount) public {
        withdrawPosition(_depositId, _amount);
        harvestPosition(_depositId);
    }

    function withdrawAndHarvestAll() public {
        uint256[] memory depositIds = allUserDepositIds[msg.sender];
        uint256 len = depositIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 depositId = depositIds[i];
            withdrawAndHarvestPosition(depositId, type(uint256).max);
        }
    }

    function stake(address _nft, uint256 _tokenId) external {
        require(acceptedNfts.contains(_nft), "NTF cannot be staked");

        userNfts[msg.sender].add(_nft);
        require(nftStaked[msg.sender][_nft].add(_tokenId), "NFT already staked");

        uint256 boost = getNftBoost(_nft, _tokenId);
        boosts[msg.sender] += boost;

        IERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);

        emit Staked(_nft, _tokenId, boosts[msg.sender]);

        _recalculateLpAmount(msg.sender);
    }

    function unstake(address _nft, uint256 _tokenId) external {
        require(nftStaked[msg.sender][_nft].remove(_tokenId), "NFT is not staked");

        if (nftStaked[msg.sender][_nft].length() == 0) {
            userNfts[msg.sender].remove(_nft);
        }

        uint256 boost = getNftBoost(_nft, _tokenId);
        boosts[msg.sender] -= boost;

        emit Unstaked(_nft, _tokenId, boosts[msg.sender]);

        _recalculateLpAmount(msg.sender);
    }

    function getNftBoost(address _nft, uint256 _tokenId) public pure returns (uint256) {
        // TODO: implement boost
        return 0;
    }

    function _recalculateLpAmount(address _user) internal {
        uint256 nftBoost = boosts[_user];

        uint256[] memory depositIds = allUserDepositIds[_user];
        uint256 len = depositIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 depositId = depositIds[i];
            UserInfo storage user = userInfo[_user][depositId];

            harvestPosition(depositId);

            (uint256 lockBoost,) = getLockBoost(user.lock);
            uint256 _amount = user.depositAmount;
            user.lpAmount = _amount + _amount * (lockBoost + nftBoost) / ONE;
        }
    }

    function allowNft(address _nft) external onlyOwner {
        require(acceptedNfts.add(_nft), "NFT already allowed");
    }

    function disallowNft(address _nft) external onlyOwner {
        require(acceptedNfts.remove(_nft), "NFT already disallowed");
    }

    function addExcludedAddress(address _exclude) external onlyOwner updateRewards {
        require(excludedAddresses.add(_exclude), "Address already excluded");
    }

    function removeExcludedAddress(address _excluded) external onlyOwner updateRewards {
        require(excludedAddresses.remove(_excluded), "Address is not excluded");
    }

    /// @notice EMERGENCY ONLY
    function toggleUnlockAll() external onlyOwner updateRewards {
        unlockAll = unlockAll ? false : true;
    }

    function withdrawUndistributedRewards() external onlyOwner updateRewards {
        uint256 _totalUndistributedRewards = totalUndistributedRewards;
        totalUndistributedRewards = 0;

        magic.safeTransfer(owner(), _totalUndistributedRewards);
        emit UndistributedRewardsWithdraw(owner(), _totalUndistributedRewards);
    }

    function _vestedPrincipal(address _user, uint256 _depositId) internal returns (uint256 amount) {
        amount = calcualteVestedPrincipal(_user, _depositId);
        UserInfo storage user = userInfo[_user][_depositId];
        user.vestingLastUpdate = block.timestamp;
    }

    function _addDeposit(address _user) internal returns (UserInfo storage user, uint256 newDepositId) {
        // start depositId from 1
        newDepositId = ++currentId[_user];
        depositIdIndex[_user][newDepositId] = allUserDepositIds[_user].length;
        allUserDepositIds[_user].push(newDepositId);
        user = userInfo[_user][newDepositId];
    }

    function _removeDeposit(address _user, uint256 _depositId) internal {
        uint256 depositIndex = depositIdIndex[_user][_depositId];

        require(allUserDepositIds[_user][depositIndex] == _depositId, 'depositId !exists');

        uint256 lastDepositIndex = allUserDepositIds[_user].length - 1;
        if (depositIndex != lastDepositIndex) {
            uint256 lastDepositId = allUserDepositIds[_user][lastDepositIndex];
            allUserDepositIds[_user][depositIndex] = lastDepositId;
            depositIdIndex[_user][lastDepositId] = depositIndex;
        }
        allUserDepositIds[_user].pop();
        delete depositIdIndex[_user][_depositId];
    }
}

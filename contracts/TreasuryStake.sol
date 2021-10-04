// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract TreasuryStake {
    using SafeERC20 for ERC20;

    uint256 public constant DAY = 60 * 60 * 24;
    uint256 public constant ONE_WEEK = DAY * 7;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;
    uint256 public constant ONE_MONTH = DAY * 30;
    uint256 public constant THREE_MONTHS = ONE_MONTH * 3;
    uint256 public constant LIFECYCLE = THREE_MONTHS;
    uint256 public constant ONE = 1e18;

    // Magic token addr
    ERC20 public immutable magic;
    ERC721 public immutable lpToken;

    uint256 public totalRewardsEarned;
    uint256 public accMagicPerShare;
    uint256 public totalLpToken;
    uint256 public undistributedRewards;

    struct UserInfo {
        uint256 tokenId;
        uint256 lpAmount;
        uint256 rewardDebt;
    }

    /// @notice user => tokenId => UserInfo
    mapping (address => mapping (uint256 => UserInfo)) public userInfo;
    /// @notice user => tokenId[]
    mapping (address => uint256[]) public allUserTokenIds;
    // tokenId => index in allUserIndex
    mapping (uint256 => uint256) public tokenIdIndex;

    event Deposit(address indexed user, uint256 lpAmount, uint256 tokenId);
    event Withdraw(address indexed user, uint256 tokenId);
    event Harvest(address indexed user, uint256 indexed index, uint256 amount);
    event LogUpdateRewards(uint256 lpSupply, uint256 accMagicPerShare);

    constructor(address _magic, address _lpToken) {
        magic = ERC20(_magic);
        lpToken = ERC721(_lpToken);
    }

    function getBoost(uint256 _tokenId) public pure returns (uint256) {
        // TODO: implement boost
        _tokenId;
        return ONE;
    }

    function pendingRewardsPosition(address _user, uint256 _tokenId) public view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user][_tokenId];
        pending = user.lpAmount * accMagicPerShare / ONE - user.rewardDebt;
    }

    function pendingRewardsAll(address _user) external view returns (uint256 pending) {
        uint256 len = allUserTokenIds[_user].length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = allUserTokenIds[msg.sender][i];
            pending += pendingRewardsPosition(_user, tokenId);
        }
    }

    function deposit(uint256 _tokenId) public {
        UserInfo storage user = _addDeposit(msg.sender, _tokenId);

        user.tokenId = _tokenId;
        uint256 lpAmount = ONE + ONE * getBoost(_tokenId) / ONE;
        user.lpAmount = lpAmount;
        totalLpToken += lpAmount;
        user.rewardDebt = lpAmount * accMagicPerShare / ONE;

        lpToken.transferFrom(msg.sender, address(this), _tokenId);

        emit Deposit(msg.sender, lpAmount, _tokenId);
    }

    function withdrawPosition(uint256 _tokenId) public {
        UserInfo storage user = userInfo[msg.sender][_tokenId];
        uint256 lpAmount = user.lpAmount;
        require(lpAmount > 0, "Position invalid");

        // Effects
        delete user.tokenId;
        delete user.lpAmount;
        delete user.rewardDebt;
        totalLpToken -= lpAmount;

        _removeDeposit(msg.sender, _tokenId);

        // Interactions
        lpToken.transferFrom(address(this), msg.sender, _tokenId);

        emit Withdraw(msg.sender, _tokenId);
    }

    function withdrawAll() public {
        uint256 len = allUserTokenIds[msg.sender].length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = allUserTokenIds[msg.sender][i];
            withdrawPosition(tokenId);
        }
    }

    function harvestPosition(uint256 _tokenId) public {
        UserInfo storage user = userInfo[msg.sender][_tokenId];

        uint256 accumulatedMagic = user.lpAmount * accMagicPerShare / ONE;
        uint256 _pendingMagic = accumulatedMagic - user.rewardDebt;

        // Effects
        user.rewardDebt = accumulatedMagic;

        // Interactions
        if (_pendingMagic != 0) {
            magic.safeTransfer(msg.sender, _pendingMagic);
        }

        emit Harvest(msg.sender, _tokenId, _pendingMagic);
    }

    function harvestAll() public {
        uint256 len = allUserTokenIds[msg.sender].length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = allUserTokenIds[msg.sender][i];
            harvestPosition(tokenId);
        }
    }

    function withdrawAndHarvestPosition(uint256 _tokenId) public {
        withdrawPosition(_tokenId);
        harvestPosition(_tokenId);
    }

    function withdrawAndHarvestAll() public {
        uint256 len = allUserTokenIds[msg.sender].length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = allUserTokenIds[msg.sender][i];
            withdrawAndHarvestPosition(tokenId);
        }
    }

    function notifyRewards(uint256 _amount) external {
        magic.safeTransferFrom(msg.sender, address(this), _amount);
        _updateRewards(_amount);
    }

    function _updateRewards(uint256 _amount) internal {
        uint256 lpSupply = totalLpToken;
        if (lpSupply > 0) {
            uint256 magicReward = _amount + undistributedRewards;
            accMagicPerShare += magicReward * ONE / lpSupply;
            undistributedRewards = 0;
        } else {
            undistributedRewards += _amount;
        }
        emit LogUpdateRewards(lpSupply, accMagicPerShare);
    }

    function _addDeposit(address _user, uint256 _tokenId) internal returns (UserInfo storage user) {
        tokenIdIndex[_tokenId] = allUserTokenIds[_user].length;
        allUserTokenIds[_user].push(_tokenId);
        user = userInfo[_user][_tokenId];
    }

    function _removeDeposit(address _user, uint256 _tokenId) internal {
        uint256 tokenIndex = tokenIdIndex[_tokenId];

        require(allUserTokenIds[_user][tokenIndex] == _tokenId, 'tokenId !exists');

        uint256 lastDepositIndex = allUserTokenIds[_user].length - 1;
        if (tokenIndex != lastDepositIndex) {
            uint256 lastDepositId = allUserTokenIds[_user][lastDepositIndex];
            allUserTokenIds[_user][tokenIndex] = lastDepositId;
            tokenIdIndex[lastDepositId] = tokenIndex;
        }

        delete allUserTokenIds[_user][lastDepositIndex];
        delete tokenIdIndex[_tokenId];
    }
}

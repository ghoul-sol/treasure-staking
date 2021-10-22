// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

contract TreasuryStake is ERC1155Holder {
    using SafeERC20 for ERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public constant DAY = 60 * 60 * 24;
    uint256 public constant ONE_WEEK = DAY * 7;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;
    uint256 public constant ONE_MONTH = DAY * 30;
    uint256 public constant THREE_MONTHS = ONE_MONTH * 3;
    uint256 public constant LIFECYCLE = THREE_MONTHS;
    uint256 public constant ONE = 1e18;

    // Magic token addr
    ERC20 public immutable magic;
    IERC1155 public immutable lpToken;

    uint256 public totalRewardsEarned;
    uint256 public accMagicPerShare;
    uint256 public totalLpToken;
    uint256 public undistributedRewards;

    struct UserInfo {
        uint256 depositAmount;
        uint256 tokenId;
        uint256 lpAmount;
        int256 rewardDebt;
    }

    /// @notice user => tokenId => UserInfo
    mapping (address => mapping (uint256 => UserInfo)) public userInfo;
    /// @notice user => tokenId[]
    mapping (address => uint256[]) public allUserTokenIds;
    // @notice user => tokenId => index in allUserIndex
    mapping (address => mapping(uint256 => uint256)) public tokenIdIndex;

    event Deposit(address indexed user, uint256 lpAmount, uint256 tokenId, uint256 depositAmount);
    event Withdraw(address indexed user, uint256 tokenId, uint256 withdrawAmount);
    event Harvest(address indexed user, uint256 indexed index, uint256 amount);
    event LogUpdateRewards(uint256 lpSupply, uint256 accMagicPerShare);

    constructor(address _magic, address _lpToken) {
        magic = ERC20(_magic);
        lpToken = IERC1155(_lpToken);
    }

    function getLpAmount(uint256 _tokenId, uint256 _amount) public pure returns (uint256) {
        uint256 boost;
        uint256 boostDecimal = 100;

        if (_tokenId == 39) { // Ancient Relic 10.03
            boost = 1003;
        } else if (_tokenId == 46) { // Bag of Rare Mushrooms 8.21
            boost = 821;
        } else if (_tokenId == 47) { // Bait for Monsters 9.73
            boost = 973;
        } else if (_tokenId == 48) { // Beetle-wing 1.00
            boost = 100;
        } else if (_tokenId == 49) { // Blue Rupee 2.04
            boost = 204;
        } else if (_tokenId == 51) { // Bottomless Elixir 10.15
            boost = 1015;
        } else if (_tokenId == 52) { // Cap of Invisibility 10.15
            boost = 1015;
        } else if (_tokenId == 53) { // Carriage 8.09
            boost = 809;
        } else if (_tokenId == 54) { // Castle 9.77
            boost = 977;
        } else if (_tokenId == 68) { // Common Bead 7.52
            boost = 752;
        } else if (_tokenId == 69) { // Common Feather 4.50
            boost = 450;
        } else if (_tokenId == 71) { // Common Relic 2.87
            boost = 287;
        } else if (_tokenId == 72) { // Cow 7.74
            boost = 774;
        } else if (_tokenId == 73) { // Diamond 1.04
            boost = 104;
        } else if (_tokenId == 74) { // Divine Hourglass 8.46
            boost = 846;
        } else if (_tokenId == 75) { // Divine Mask 7.62
            boost = 762;
        } else if (_tokenId == 76) { // Donkey 1.62
            boost = 162;
        } else if (_tokenId == 77) { // Dragon Tail 1.03
            boost = 103;
        } else if (_tokenId == 79) { // Emerald 1.01
            boost = 101;
        } else if (_tokenId == 82) { // Favor from the Gods 7.39
            boost = 739;
        } else if (_tokenId == 91) { // Framed Butterfly 7.79
            boost = 779;
        } else if (_tokenId == 92) { // Gold Coin 1.03
            boost = 103;
        } else if (_tokenId == 93) { // Grain 4.29
            boost = 429;
        } else if (_tokenId == 94) { // Green Rupee 4.36
            boost = 436;
        } else if (_tokenId == 95) { // Grin 10.47
            boost = 1047;
        } else if (_tokenId == 96) { // Half-Penny 1.05
            boost = 105;
        } else if (_tokenId == 97) { // Honeycomb 10.52
            boost = 1052;
        } else if (_tokenId == 98) { // Immovable Stone 9.65
            boost = 965;
        } else if (_tokenId == 99) { // Ivory Breastpin 8.49
            boost = 849;
        } else if (_tokenId == 100) { // Jar of Fairies 7.10
            boost = 710;
        } else if (_tokenId == 103) { // Lumber 4.02
            boost = 402;
        } else if (_tokenId == 104) { // Military Stipend 8.30
            boost = 830;
        } else if (_tokenId == 105) { // Mollusk Shell 8.96
            boost = 896;
        } else if (_tokenId == 114) { // Ox 2.12
            boost = 212;
        } else if (_tokenId == 115) { // Pearl 1.03
            boost = 103;
        } else if (_tokenId == 116) { // Pot of Gold 7.72
            boost = 772;
        } else if (_tokenId == 117) { // Quarter-Penny 1.00
            boost = 100;
        } else if (_tokenId == 132) { // Red Feather 8.51
            boost = 851;
        } else if (_tokenId == 133) { // Red Rupee 1.03
            boost = 103;
        } else if (_tokenId == 141) { // Score of Ivory 7.94
            boost = 794;
        } else if (_tokenId == 151) { // Silver Coin 1.05
            boost = 105;
        } else if (_tokenId == 152) { // Small Bird 7.98
            boost = 798;
        } else if (_tokenId == 153) { // Snow White Feather 8.54
            boost = 854;
        } else if (_tokenId == 161) { // Thread of Divine Silk 9.77
            boost = 977;
        } else if (_tokenId == 162) { // Unbreakable Pocketwatch 7.91
            boost = 791;
        } else if (_tokenId == 164) { // Witches Broom 6.76
            boost = 676;
        } else {
            boost = 0;
        }
        _amount = addDecimals(_amount);
        return _amount + _amount * boost / boostDecimal;
    }

    function addDecimals(uint256 _amount) public pure returns (uint256) {
        return _amount * ONE;
    }

    function getAllUserTokenIds(address _user) public view returns (uint256[] memory) {
        return allUserTokenIds[_user];
    }

    function pendingRewardsPosition(address _user, uint256 _tokenId) public view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user][_tokenId];
        pending = ((user.lpAmount * accMagicPerShare / ONE).toInt256() - user.rewardDebt).toUint256();
    }

    function pendingRewardsAll(address _user) external view returns (uint256 pending) {
        uint256 len = allUserTokenIds[_user].length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = allUserTokenIds[_user][i];
            pending += pendingRewardsPosition(_user, tokenId);
        }
    }

    function deposit(uint256 _tokenId, uint256 _amount) public {
        UserInfo storage user = _addDeposit(msg.sender, _tokenId);

        uint256 lpAmount = getLpAmount(_tokenId, _amount);
        totalLpToken += lpAmount;

        user.tokenId = _tokenId;
        user.depositAmount += _amount;
        user.lpAmount += lpAmount;
        user.rewardDebt += (lpAmount * accMagicPerShare / ONE).toInt256();

        lpToken.safeTransferFrom(msg.sender, address(this), _tokenId, _amount, bytes(""));

        emit Deposit(msg.sender, lpAmount, _tokenId, _amount);
    }

    function withdrawPosition(uint256 _tokenId, uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender][_tokenId];
        uint256 lpAmount = user.lpAmount;
        uint256 depositAmount = user.depositAmount;
        require(depositAmount > 0, "Position does not exists");

        if (_amount > depositAmount) {
            _amount = depositAmount;
        }

        // Effects
        uint256 ratio = _amount * ONE / depositAmount;
        lpAmount = lpAmount * ratio / ONE;

        totalLpToken -= lpAmount;

        user.depositAmount -= _amount;
        user.lpAmount -= lpAmount;
        user.rewardDebt -= (lpAmount * accMagicPerShare / ONE).toInt256();

        // Interactions
        lpToken.safeTransferFrom(address(this), msg.sender, _tokenId, _amount, bytes(""));

        emit Withdraw(msg.sender, _tokenId, _amount);
    }

    function withdrawAll() public {
        uint256[] memory tokenIds = allUserTokenIds[msg.sender];
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = tokenIds[i];
            withdrawPosition(tokenId, type(uint256).max);
        }
    }

    function harvestPosition(uint256 _tokenId) public {
        UserInfo storage user = userInfo[msg.sender][_tokenId];

        int256 accumulatedMagic = (user.lpAmount * accMagicPerShare / ONE).toInt256();
        uint256 _pendingMagic = (accumulatedMagic - user.rewardDebt).toUint256();

        // Effects
        user.rewardDebt = accumulatedMagic;

        if (user.lpAmount == 0) {
            _removeDeposit(msg.sender, _tokenId);
        }

        // Interactions
        if (_pendingMagic != 0) {
            magic.safeTransfer(msg.sender, _pendingMagic);
        }

        emit Harvest(msg.sender, _tokenId, _pendingMagic);
    }

    function harvestAll() public {
        uint256[] memory tokenIds = allUserTokenIds[msg.sender];
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = tokenIds[i];
            harvestPosition(tokenId);
        }
    }

    function withdrawAndHarvestPosition(uint256 _tokenId, uint256 _amount) public {
        withdrawPosition(_tokenId, _amount);
        harvestPosition(_tokenId);
    }

    function withdrawAndHarvestAll() public {
        uint256[] memory tokenIds = allUserTokenIds[msg.sender];
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = tokenIds[i];
            withdrawAndHarvestPosition(tokenId, type(uint256).max);
        }
    }

    function notifyRewards(uint256 _amount) external {
        if (_amount != 0) magic.safeTransferFrom(msg.sender, address(this), _amount);
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
        user = userInfo[_user][_tokenId];
        uint256 tokenIndex = tokenIdIndex[_user][_tokenId];
        if (allUserTokenIds[_user].length == 0 || allUserTokenIds[_user][tokenIndex] != _tokenId) {
            tokenIdIndex[_user][_tokenId] = allUserTokenIds[_user].length;
            allUserTokenIds[_user].push(_tokenId);
        }
    }

    function _removeDeposit(address _user, uint256 _tokenId) internal {
        uint256 tokenIndex = tokenIdIndex[_user][_tokenId];

        require(allUserTokenIds[_user][tokenIndex] == _tokenId, 'tokenId !exists');

        uint256 lastDepositIndex = allUserTokenIds[_user].length - 1;
        if (tokenIndex != lastDepositIndex) {
            uint256 lastDepositId = allUserTokenIds[_user][lastDepositIndex];
            allUserTokenIds[_user][tokenIndex] = lastDepositId;
            tokenIdIndex[_user][lastDepositId] = tokenIndex;
        }

        allUserTokenIds[_user].pop();
        delete tokenIdIndex[_user][_tokenId];
    }
}

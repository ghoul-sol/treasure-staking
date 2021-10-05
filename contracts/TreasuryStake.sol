// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';

contract TreasuryStake {
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
    ERC721 public immutable lpToken;

    uint256 public totalRewardsEarned;
    uint256 public accMagicPerShare;
    uint256 public totalLpToken;
    uint256 public undistributedRewards;

    struct UserInfo {
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

    event Deposit(address indexed user, uint256 lpAmount, uint256 tokenId);
    event Withdraw(address indexed user, uint256 tokenId);
    event Harvest(address indexed user, uint256 indexed index, uint256 amount);
    event LogUpdateRewards(uint256 lpSupply, uint256 accMagicPerShare);

    constructor(address _magic, address _lpToken) {
        magic = ERC20(_magic);
        lpToken = ERC721(_lpToken);
    }

    function getLpAmount(uint256 _tokenId) public pure returns (uint256) {
        uint256 boost;
        uint256 boostDecimal = 1e10;

        // TODO: set proper token ids
        if (_tokenId == 0) { // Honeycomb	10.5232558139535
            boost = 105232558139;
        } else if (_tokenId == 1) { // Grin	10.474537037037
            boost = 104745370370;
        } else if (_tokenId == 2) { // Cap of Invisibility	10.1457399103139
            boost = 101457399103;
        } else if (_tokenId == 3) { // Bottomless Elixir	10.1457399103139
            boost = 101457399103;
        } else if (_tokenId == 1) { // Ancient Relic	10.0332594235033
            boost = 100332594235;
        } else if (_tokenId == 1) { // Thread of Divine Silk	9.7732181425486
            boost = 97732181425;
        } else if (_tokenId == 1) { // Castle	9.7732181425486
            boost = 97732181425;
        } else if (_tokenId == 1) { // Bait for Monster	9.73118279569892
            boost = 97311827956;
        } else if (_tokenId == 1) { // Immovable Stone	9.64818763326226
            boost = 96481876332;
        } else if (_tokenId == 1) { // Mollusk Shell	8.96039603960396
            boost = 89603960396;
        } else if (_tokenId == 1) { // Red FeatherSnowWhiteFeather	8.5377358490566
            boost = 85377358490;
        } else if (_tokenId == 1) { // Red Feather	8.50563909774436
            boost = 85056390977;
        } else if (_tokenId == 1) { // Ivory Breastpin	8.48968105065666
            boost = 84896810506;
        } else if (_tokenId == 1) { // Divine Hourglass	8.45794392523364
            boost = 84579439252;
        } else if (_tokenId == 1) { // Military Stipend	8.30275229357798
            boost = 83027522935;
        } else if (_tokenId == 1) { // Bag of Rare Mushrooms	8.21234119782214
            boost = 82123411978;
        } else if (_tokenId == 1) { // Carriage	8.09481216457961
            boost = 80948121645;
        } else if (_tokenId == 1) { // Small Bird	7.98059964726631
            boost = 79805996472;
        } else if (_tokenId == 1) { // Score of Ivory	7.93859649122807
            boost = 79385964912;
        } else if (_tokenId == 1) { // Unbreakable Pocketwatch	7.91083916083916
            boost = 79108391608;
        } else if (_tokenId == 1) { // Framed Butterfly	7.78829604130809
            boost = 77882960413;
        } else if (_tokenId == 1) { // Cow	7.73504273504274
            boost = 77350427350;
        } else if (_tokenId == 1) { // Pot of Gold	7.72184300341297
            boost = 77218430034;
        } else if (_tokenId == 1) { // Divine Mask	7.61784511784512
            boost = 76178451178;
        } else if (_tokenId == 1) { // Common Bead	7.51661129568106
            boost = 75166112956;
        } else if (_tokenId == 1) { // Favor from the Gods	7.3937908496732
            boost = 73937908496;
        } else if (_tokenId == 1) { // Jar of Fairies	7.10361067503925
            boost = 71036106750;
        } else if (_tokenId == 1) { // Witches Broom	6.76382660687593
            boost = 67638266068;
        } else if (_tokenId == 1) { // Common Feather	4.50248756218905
            boost = 45024875621;
        } else if (_tokenId == 1) { // Green Rupee	4.35934489402698
            boost = 43593448940;
        } else if (_tokenId == 1) { // Grain	4.29316888045541
            boost = 42931688804;
        } else if (_tokenId == 1) { // Lumber	4.02222222222222
            boost = 40222222222;
        } else if (_tokenId == 1) { // Common Relic	2.87119289340102
            boost = 28711928934;
        } else if (_tokenId == 1) { // Ox	2.11646398503274
            boost = 21164639850;
        } else if (_tokenId == 1) { // Blue Rupee	2.03645364536454
            boost = 20364536453;
        } else if (_tokenId == 1) { // Donkey	1.62360961607463
            boost = 16236096160;
        } else if (_tokenId == 1) { // Half-Penny	1.04624277456647
            boost = 10462427745;
        } else if (_tokenId == 1) { // Silver Penny	1.04503464203233
            boost = 10450346420;
        } else if (_tokenId == 1) { // Diamond	1.04190651623302
            boost = 10419065162;
        } else if (_tokenId == 1) { // Pearl	1.03334094542133
            boost = 10333409454;
        } else if (_tokenId == 1) { // Dragon Tail	1.02747502270663
            boost = 10274750227;
        } else if (_tokenId == 1) { // Red Rupee	1.02677558429771
            boost = 10267755842;
        } else if (_tokenId == 1) { // Gold Coin	1.02537956038976
            boost = 10253795603;
        } else if (_tokenId == 1) { // Emerald	1.01004464285714
            boost = 10100446428;
        } else if (_tokenId == 1) { // Beetle-wing	1.00310352471736
            boost = 10031035247;
        } else if (_tokenId == 1) { // Quarter-Penny	1
            boost = 10000000000;
        } else {
            boost = 0;
        }
        return ONE + ONE * boost / boostDecimal;
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

    function deposit(uint256 _tokenId) public {
        UserInfo storage user = _addDeposit(msg.sender, _tokenId);

        uint256 lpAmount = getLpAmount(_tokenId);
        totalLpToken += lpAmount;

        user.tokenId = _tokenId;
        user.lpAmount = lpAmount;
        user.rewardDebt += (lpAmount * accMagicPerShare / ONE).toInt256();

        lpToken.transferFrom(msg.sender, address(this), _tokenId);

        emit Deposit(msg.sender, lpAmount, _tokenId);
    }

    function withdrawPosition(uint256 _tokenId) public {
        UserInfo storage user = userInfo[msg.sender][_tokenId];
        uint256 lpAmount = user.lpAmount;
        require(lpAmount > 0, "Position invalid");

        // Effects
        totalLpToken -= lpAmount;

        user.tokenId -= _tokenId;
        user.lpAmount -= lpAmount;
        user.rewardDebt -= (lpAmount * accMagicPerShare / ONE).toInt256();

        // Interactions
        lpToken.transferFrom(address(this), msg.sender, _tokenId);

        emit Withdraw(msg.sender, _tokenId);
    }

    function withdrawAll() public {
        uint256[] memory tokenIds = allUserTokenIds[msg.sender];
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = tokenIds[i];
            withdrawPosition(tokenId);
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

    function withdrawAndHarvestPosition(uint256 _tokenId) public {
        withdrawPosition(_tokenId);
        harvestPosition(_tokenId);
    }

    function withdrawAndHarvestAll() public {
        uint256[] memory tokenIds = allUserTokenIds[msg.sender];
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 tokenId = tokenIds[i];
            withdrawAndHarvestPosition(tokenId);
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
        tokenIdIndex[_user][_tokenId] = allUserTokenIds[_user].length;
        allUserTokenIds[_user].push(_tokenId);
        user = userInfo[_user][_tokenId];
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

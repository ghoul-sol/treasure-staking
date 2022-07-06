pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import "contracts/AtlasMine.sol";
import "forge-std/console2.sol";
import "foundry/lib/ERC20Mintable.sol";

contract AtlasMineMock is AtlasMine {
    constructor(address _magic, address _masterOfCoin) {
        magic = IERC20Upgradeable(_magic);
        masterOfCoin = IMasterOfCoin(_masterOfCoin);

        _setRoleAdmin(ATLAS_MINE_ADMIN_ROLE, ATLAS_MINE_ADMIN_ROLE);
        _grantRole(ATLAS_MINE_ADMIN_ROLE, msg.sender);

        // array follows values from ILegionMetadataStore.LegionGeneration and ILegionMetadataStore.LegionRarity
        legionBoostMatrix = [
            // GENESIS
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(600e16), uint256(200e16), uint256(75e16), uint256(100e16), uint256(50e16), uint256(0)],
            // AUXILIARY
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(0), uint256(25e16), uint256(0), uint256(10e16), uint256(5e16), uint256(0)],
            // RECRUIT
            // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
            [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)]
        ];
    }

    function setUserInfo(address _user, uint256 _depositId, UserInfo memory _userInfo) public {
        currentId[_user] = _depositId - 1;
        _addDeposit(_user);

        userInfo[_user][_depositId] = _userInfo;
    }

    function setAccMagicPerShare(uint256 _accMagicPerShare) public {
        accMagicPerShare = _accMagicPerShare;
    }

    function setMagicTotalDeposits(uint256 _magicTotalDeposits) public {
        magicTotalDeposits = _magicTotalDeposits;
    }

    function setTotalLpToken(uint256 _totalLpToken) public {
        totalLpToken = _totalLpToken;
    }
}

contract MasterOfCoinMock {
    function requestRewards() public returns (uint256 rewards){}
    function getPendingRewards(address _harvester) public returns (uint256 rewards) {}
}

contract AtlasMineTest is TestUtils {
    address public buggyUserAddr = 0xA094629baAE6aF0C43F17F434B975337cBDb3C42;
    uint256 buggyDepositId = 48;

    MasterOfCoinMock masterOfCoin;
    ERC20Mintable magic;

    AtlasMineMock public atlasMineMock;

    function setUp() public {
        magic = new ERC20Mintable();
        masterOfCoin = new MasterOfCoinMock();

        atlasMineMock = new AtlasMineMock(address(magic), address(masterOfCoin));
    }

    // setup local env with data pulled from arbitrum to simulate the issue
    function setupForRoundingError() public {
        // Logs:
        //   originalDepositAmount, 430387086000000000000000
        //   depositAmount, 74380162410634787765876
        //   lpAmount, 1060289215163598920875547
        //   lockedUntil, 1651019875
        //   vestingLastUpdate, 1656571398
        //   rewardDebt 23897933140717558592054
        //   AtlasMine.Lock, 0

        // Logs:
        //   originalDepositAmount, 430387086000000000000000
        //   depositAmount, 0
        //   lpAmount, 0
        //   lockedUntil, 1651019875
        //   vestingLastUpdate, 1656571398
        //   rewardDebt 1
        //   AtlasMine.Lock, 0

        uint256 totalSupply = 178155228707911350010388374;

        address[6] memory excludedAddresses = [
            0x482729215AAF99B3199E41125865821ed5A4978a,
            0xDb6Ab450178bAbCf0e467c1F3B436050d907E233,
            0x78aB1f527d8a9758c6BbA1adf812B5CfEaa7ab71,
            0x1a9c20e2b0aC11EBECbDCA626BBA566c4ce8e606,
            0x3563590E19d2B9216E7879D269a04ec67Ed95A87,
            0xf9E197Aa9fa7C3b27A1A1313CaD5851B55F2FD71
        ];

        uint256[6] memory excludedBalances = [
            uint256(3403214005496119790531452),
            2410379655614358944445344,
            76054553056580374020742,
            884141382286248118237095,
            6795145771156198527807620,
            4059037137500000000005364
        ];

        uint256 atlasMineMockBalance = 114174576351167687293554022;

        uint256 leftSupply = totalSupply - atlasMineMockBalance;
        for (uint256 i = 0; i < excludedAddresses.length; i++) {
            magic.mint(excludedAddresses[i], excludedBalances[i]);
            leftSupply -= excludedBalances[i];
        }

        magic.mint(address(atlasMineMock), atlasMineMockBalance);
        magic.mint(address(999), leftSupply);

        atlasMineMock.setTotalLpToken(1027033503589228922056954643);
        atlasMineMock.setMagicTotalDeposits(111745440420546839078610661);
        atlasMineMock.setAccMagicPerShare(22539070282847488);

        atlasMineMock.setUserInfo(
            buggyUserAddr,
            buggyDepositId,
            AtlasMine.UserInfo({
                originalDepositAmount: 430387086000000000000000,
                depositAmount: 74380162410634787765876,
                lpAmount: 1060289215163598920875547,
                lockedUntil: 1651019875,
                vestingLastUpdate: 1656571398,
                rewardDebt: 23897933140717558592054,
                lock: AtlasMine.Lock.twoWeeks
            })
        );

        // block.number, 16564676
        uint256 blockTimestampBeforeIssue = 1656571398;
        vm.warp(blockTimestampBeforeIssue);
    }

    function viewUserInfo(AtlasMine _atlasMine, address _user, uint256 _depositId, bool _display)
        public
        view
        returns (
            uint256 originalDepositAmount,
            uint256 depositAmount,
            uint256 lpAmount,
            uint256 lockedUntil,
            uint256 vestingLastUpdate,
            int256 rewardDebt,
            AtlasMine.Lock lock
        )
    {
        (
            originalDepositAmount,
            depositAmount,
            lpAmount,
            lockedUntil,
            vestingLastUpdate,
            rewardDebt,
            lock
        ) = _atlasMine.userInfo(_user, _depositId);

        if (_display) {
            console2.log("##### VIEW BEGIN #####");
            console2.log("originalDepositAmount", originalDepositAmount);
            console2.log("depositAmount", depositAmount);
            console2.log("lpAmount", lpAmount);
            console2.log("lockedUntil", lockedUntil);
            console2.log("vestingLastUpdate", vestingLastUpdate);
            console2.log("rewardDebt");
            console2.logInt(rewardDebt);
            console2.log(uint256(rewardDebt));
            console2.log("AtlasMine.Lock", uint256(lock));
            console2.log("##### VIEW END #####");
        }
    }

    function test_roundingErrorScenario() public {
        // convenience var for logs
        bool DISPLAY_VALUES = false;

        setupForRoundingError();

        assertEq(atlasMineMock.pendingRewardsPosition(buggyUserAddr, buggyDepositId), 0);

        (, uint256 depositAmount, uint256 lpAmount,,, int256 rewardDebt,)
            = viewUserInfo(atlasMineMock, buggyUserAddr, buggyDepositId, DISPLAY_VALUES);

        assertEq(depositAmount, 74380162410634787765876);
        assertEq(lpAmount, 1060289215163598920875547);
        assertEq(rewardDebt, 23897933140717558592054);

        vm.prank(buggyUserAddr);
        atlasMineMock.withdrawPosition(buggyDepositId, depositAmount);

        assertEq(atlasMineMock.pendingRewardsPosition(buggyUserAddr, buggyDepositId), 0);

        (, depositAmount, lpAmount,,, rewardDebt,)
            = viewUserInfo(atlasMineMock, buggyUserAddr, buggyDepositId, DISPLAY_VALUES);

        assertEq(depositAmount, 0);
        assertEq(lpAmount, 0);
        assertEq(rewardDebt, 1);

        vm.prank(buggyUserAddr);
        atlasMineMock.harvestAll();

        assertEq(atlasMineMock.pendingRewardsPosition(buggyUserAddr, buggyDepositId), 0);

        (, depositAmount, lpAmount,,, rewardDebt,)
            = viewUserInfo(atlasMineMock, buggyUserAddr, buggyDepositId, DISPLAY_VALUES);

        assertEq(depositAmount, 0);
        assertEq(lpAmount, 0);
        assertEq(rewardDebt, 0);
    }
}

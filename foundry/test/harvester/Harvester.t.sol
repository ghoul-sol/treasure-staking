pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/ERC20Mintable.sol";

import "contracts/harvester/Harvester.sol";

contract HarvesterMock is Harvester {
    function addDeposit(address _user) public returns (UserInfo memory user, uint256 newDepositId) {
        return super._addDeposit(_user);
    }

    function removeDeposit(address _user, uint256 _depositId) public {
        super._removeDeposit(_user, _depositId);
    }

    function setGlobalDepositAmount(address _user, uint256 _amount) public {
        GlobalUserDeposit storage g = getUserGlobalDeposit[_user];
        g.globalDepositAmount = _amount;
    }
}

contract MiddlemanMock {
    ERC20Mintable public magic;

    constructor (ERC20Mintable _magic) {
        magic = _magic;
    }

    function setReward(uint256 _reward) public {
        magic.mint(address(this), _reward);
    }

    function requestRewards() public returns (uint256 rewards){
        rewards = magic.balanceOf(address(this));
        magic.transfer(msg.sender, rewards);
    }

    function getPendingRewards(address _harvester) public returns (uint256 rewards) {}
}

contract HarvesterTest is TestUtils {
    Harvester public harvester;

    address public admin = address(111);
    address public nftHandler = address(222);
    address public parts = address(333);
    address public harvesterFactory = address(this);
    address public randomWallet = address(444);
    address public middleman = address(555);
    address public stakingRules = address(665);

    address public user1 = address(1001);
    address public user2 = address(1002);
    address public user3 = address(1003);

    ERC20Mintable public magic;
    MiddlemanMock public middlemanMock;

    uint256 public initTotalDepositCap = 10_000_000e18;

    IHarvester.CapConfig public initDepositCapPerWallet = IHarvester.CapConfig({
        parts: parts,
        capPerPart: 1e18
    });

    event NftHandler(INftHandler _nftHandler);
    event DepositCapPerWallet(IHarvester.CapConfig _depositCapPerWallet);
    event TotalDepositCap(uint256 _totalDepositCap);
    event UnlockAll(bool _value);
    event Enable();
    event Disable();
    event Deposit(address indexed user, uint256 indexed index, uint256 amount, uint256 lock);
    event Withdraw(address indexed user, uint256 indexed index, uint256 amount);
    event Harvest(address indexed user, uint256 amount);
    event TimelockOption(IHarvester.Timelock timelock, uint256 id);
    event TimelockOptionEnabled(IHarvester.Timelock timelock, uint256 id);
    event TimelockOptionDisabled(IHarvester.Timelock timelock, uint256 id);

    function setUp() public {
        vm.label(admin, "admin");
        vm.label(nftHandler, "nftHandler");

        harvester = new Harvester();
        harvester.init(admin, INftHandler(nftHandler), initDepositCapPerWallet);

        magic = new ERC20Mintable();
        vm.mockCall(harvesterFactory, abi.encodeCall(IHarvesterFactory.magic, ()), abi.encode(address(magic)));

        middlemanMock = new MiddlemanMock(magic);
    }

    function test_init() public {
        assertTrue(harvester.hasRole(harvester.HARVESTER_ADMIN(), admin));
        assertEq(harvester.getRoleAdmin(harvester.HARVESTER_ADMIN()), harvester.HARVESTER_ADMIN());
        assertEq(harvester.totalDepositCap(), initTotalDepositCap);
        assertEq(address(harvester.factory()), harvesterFactory);
        assertEq(address(harvester.nftHandler()), nftHandler);

        (address initParts, uint256 initCapPerPart) = harvester.depositCapPerWallet();
        assertEq(initParts, initDepositCapPerWallet.parts);
        assertEq(initCapPerPart, initDepositCapPerWallet.capPerPart);
    }



    function test_getTimelockOptionsIds() public {
        uint256[] memory expectedIds = new uint256[](5);

        for (uint256 i = 0; i < 5; i++) {
            expectedIds[i] = i;
        }

        uint256[] memory ids = harvester.getTimelockOptionsIds();

        assertUint256ArrayEq(ids, expectedIds);
    }

    function test_getUserBoost(address _user, uint256 _boost) public {
        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getUserBoost, (_user)), abi.encode(_boost));
        assertEq(harvester.getUserBoost(_user), _boost);
    }

    function test_getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount, uint256 _boost) public {
        vm.mockCall(
            nftHandler,
            abi.encodeCall(INftHandler.getNftBoost, (_user, _nft, _tokenId, _amount)),
            abi.encode(_boost)
        );
        assertEq(harvester.getNftBoost(_user, _nft, _tokenId, _amount), _boost);
    }

    function deployMockHarvester() public returns (HarvesterMock) {
        HarvesterMock mockHarvester = new HarvesterMock();
        mockHarvester.init(admin, INftHandler(nftHandler), initDepositCapPerWallet);
        return mockHarvester;
    }

    function test_getAllUserDepositIds_getAllUserDepositIdsLength() public {
        HarvesterMock mockHarvester = deployMockHarvester();

        uint256 newDepositId;

        (, newDepositId) = mockHarvester.addDeposit(user1);
        assertEq(newDepositId, 1);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user1), 1);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[0], 1);

        (, newDepositId) = mockHarvester.addDeposit(user1);
        assertEq(newDepositId, 2);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user1), 2);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[0], 1);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[1], 2);

        (, newDepositId) = mockHarvester.addDeposit(user1);
        assertEq(newDepositId, 3);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user1), 3);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[0], 1);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[1], 2);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[2], 3);

        mockHarvester.removeDeposit(user1, 2);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user1), 2);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[0], 1);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[1], 3);

        (, newDepositId) = mockHarvester.addDeposit(user2);
        assertEq(newDepositId, 1);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user2), 1);
        assertEq(mockHarvester.getAllUserDepositIds(user2)[0], 1);

        vm.expectRevert("DepositDoesNotExists()");
        mockHarvester.removeDeposit(user2, 2);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user2), 1);
        assertEq(mockHarvester.getAllUserDepositIds(user2)[0], 1);

        mockHarvester.removeDeposit(user2, 1);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user2), 0);

        (, newDepositId) = mockHarvester.addDeposit(user2);
        assertEq(newDepositId, 2);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user2), 1);
        assertEq(mockHarvester.getAllUserDepositIds(user2)[0], 2);

        (, newDepositId) = mockHarvester.addDeposit(user2);
        assertEq(newDepositId, 3);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user2), 2);
        assertEq(mockHarvester.getAllUserDepositIds(user2)[0], 2);
        assertEq(mockHarvester.getAllUserDepositIds(user2)[1], 3);

        (, newDepositId) = mockHarvester.addDeposit(user1);
        assertEq(newDepositId, 4);
        assertEq(mockHarvester.getAllUserDepositIdsLength(user1), 3);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[0], 1);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[1], 3);
        assertEq(mockHarvester.getAllUserDepositIds(user1)[2], 4);
    }

    function test_getUserDepositCap() public {
        uint256 amountStaked = 20;

        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getStakingRules, (parts)), abi.encode(address(0)));
        assertEq(harvester.getUserDepositCap(user1), 0);

        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getStakingRules, (parts)), abi.encode(stakingRules));
        vm.mockCall(stakingRules, abi.encodeCall(IPartsStakingRules.getAmountStaked, (user1)), abi.encode(amountStaked));

        assertEq(harvester.getUserDepositCap(user1), amountStaked * initDepositCapPerWallet.capPerPart);
    }

    function test_isMaxUserGlobalDeposit() public {
        HarvesterMock mockHarvester = deployMockHarvester();

        uint256 amountStaked = 5;

        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getStakingRules, (parts)), abi.encode(address(0)));

        assertFalse(mockHarvester.isMaxUserGlobalDeposit(user1));

        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getStakingRules, (parts)), abi.encode(stakingRules));
        vm.mockCall(stakingRules, abi.encodeCall(IPartsStakingRules.getAmountStaked, (user1)), abi.encode(amountStaked));

        assertFalse(mockHarvester.isMaxUserGlobalDeposit(user1));

        mockHarvester.setGlobalDepositAmount(user1, initDepositCapPerWallet.capPerPart * amountStaked);

        assertFalse(mockHarvester.isMaxUserGlobalDeposit(user1));

        mockHarvester.setGlobalDepositAmount(user1, initDepositCapPerWallet.capPerPart * amountStaked + 1);

        assertTrue(mockHarvester.isMaxUserGlobalDeposit(user1));
    }

    function test_getLockBoost() public {
        uint256 boost;
        uint256 timelock;

        (boost, timelock) = harvester.getLockBoost(0);
        assertEq(boost, 0.1e18);
        assertEq(timelock, harvester.TWO_WEEKS());

        (boost, timelock) = harvester.getLockBoost(1);
        assertEq(boost, 0.25e18);
        assertEq(timelock, harvester.ONE_MONTH());

        (boost, timelock) = harvester.getLockBoost(2);
        assertEq(boost, 0.8e18);
        assertEq(timelock, harvester.THREE_MONTHS());

        (boost, timelock) = harvester.getLockBoost(3);
        assertEq(boost, 1.8e18);
        assertEq(timelock, harvester.SIX_MONTHS());

        (boost, timelock) = harvester.getLockBoost(4);
        assertEq(boost, 4e18);
        assertEq(timelock, harvester.TWELVE_MONTHS());
    }

    function test_getVestingTime() public {
        assertEq(harvester.getVestingTime(0), 0);
        assertEq(harvester.getVestingTime(1), 7 days);
        assertEq(harvester.getVestingTime(2), 14 days);
        assertEq(harvester.getVestingTime(3), 30 days);
        assertEq(harvester.getVestingTime(4), 45 days);
    }

    function test_enable() public {
        vm.prank(harvesterFactory);
        harvester.disable();

        assertTrue(harvester.disabled());

        vm.prank(randomWallet);
        vm.expectRevert("OnlyFactory()");
        harvester.enable();

        vm.prank(harvesterFactory);
        vm.expectEmit(true, true, true, true);
        emit Enable();
        harvester.enable();

        assertFalse(harvester.disabled());
    }

    function test_disable() public {
        assertFalse(harvester.disabled());

        vm.prank(randomWallet);
        vm.expectRevert("OnlyFactory()");
        harvester.disable();

        vm.prank(harvesterFactory);
        vm.expectEmit(true, true, true, true);
        emit Disable();
        harvester.disable();

        assertTrue(harvester.disabled());
    }

    enum Actions { Deposit, Withdraw, WithdrawAll, Harvest, WithdrawAndHarvest, WithdrawAndHarvestAll }

    struct TestAction {
        Actions action;
        address user;
        uint256 depositId;
        uint256 nftBoost;
        uint256 timeTravel;
        uint256 requestRewards;
        uint256 withdrawAmount;
        uint256 lock;
        uint256 originalDepositAmount;
        uint256 depositAmount;
        uint256 lockLpAmount;
        uint256 lockedUntil;
        uint256 globalDepositAmount;
        uint256 globalLockLpAmount;
        uint256 globalLpAmount;
        int256 globalRewardDebt;
        uint256 magicTotalDeposits;
        uint256 totalLpToken;
        uint256 accMagicPerShare;
        uint256 pendingRewardsBefore;
        uint256 pendingRewards;
        bytes revertString;
    }

    // workaround for "UnimplementedFeatureError: Copying of type struct memory to storage not yet supported."
    uint256 public constant depositTestCasesLength = 9;

    function getTestAction(uint256 _index) public view returns (TestAction memory) {
        TestAction[depositTestCasesLength] memory testDepositCases = [
            // TODO: add more tests
            TestAction({
                action: Actions.Deposit,
                user: user1,
                depositId: 1,
                nftBoost: 0.5e18,
                timeTravel: 0,
                requestRewards: 0,
                withdrawAmount: 0,
                lock: 0,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.1e18,
                lockedUntil: 0,
                globalDepositAmount: 1e18,
                globalLockLpAmount: 1.1e18,
                globalLpAmount: 1.65e18,
                globalRewardDebt: 0,
                magicTotalDeposits: 1e18,
                totalLpToken: 1.65e18,
                accMagicPerShare: 0,
                pendingRewardsBefore: 0,
                pendingRewards: 0,
                revertString: ""
            }),
            TestAction({
                action: Actions.Deposit,
                user: user2,
                depositId: 1,
                nftBoost: 0.8e18,
                timeTravel: 0,
                requestRewards: 0.1e18,
                withdrawAmount: 0,
                lock: 2,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.8e18,
                lockedUntil: 0,
                globalDepositAmount: 1e18,
                globalLockLpAmount: 1.8e18,
                globalLpAmount: 3.24e18,
                globalRewardDebt: 0.196363636363636363e18,
                magicTotalDeposits: 2e18,
                totalLpToken: 4.89e18,
                accMagicPerShare: 0.060606060606060606e18,
                pendingRewardsBefore: 0,
                pendingRewards: 0,
                revertString: ""
            }),
            TestAction({
                action: Actions.Harvest,
                user: user1,
                depositId: 1,
                nftBoost: 0.5e18,
                timeTravel: 0,
                requestRewards: 0,
                withdrawAmount: 0,
                lock: 0,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.1e18,
                lockedUntil: 0,
                globalDepositAmount: 1e18,
                globalLockLpAmount: 1.1e18,
                globalLpAmount: 1.65e18,
                globalRewardDebt: 0.099999999999999999e18,
                magicTotalDeposits: 2e18,
                totalLpToken: 4.89e18,
                accMagicPerShare: 0.060606060606060606e18,
                pendingRewardsBefore: 0.099999999999999999e18,
                pendingRewards: 0,
                revertString: ""
            }),
            TestAction({
                action: Actions.Withdraw,
                user: user1,
                depositId: 1,
                nftBoost: 0.5e18,
                timeTravel: 0,
                requestRewards: 0,
                withdrawAmount: 0,
                lock: 0,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.1e18,
                lockedUntil: 0,
                globalDepositAmount: 1e18,
                globalLockLpAmount: 1.1e18,
                globalLpAmount: 1.65e18,
                globalRewardDebt: 0.099999999999999999e18,
                magicTotalDeposits: 2e18,
                totalLpToken: 4.89e18,
                accMagicPerShare: 0.060606060606060606e18,
                pendingRewardsBefore: 0,
                pendingRewards: 0,
                revertString: "ZeroAmount()"
            }),
            TestAction({
                action: Actions.Withdraw,
                user: user1,
                depositId: 1,
                nftBoost: 0.5e18,
                timeTravel: 0,
                requestRewards: 0,
                withdrawAmount: 1e18,
                lock: 0,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.1e18,
                lockedUntil: 0,
                globalDepositAmount: 1e18,
                globalLockLpAmount: 1.1e18,
                globalLpAmount: 1.65e18,
                globalRewardDebt: 0.099999999999999999e18,
                magicTotalDeposits: 2e18,
                totalLpToken: 4.89e18,
                accMagicPerShare: 0.060606060606060606e18,
                pendingRewardsBefore: 0,
                pendingRewards: 0,
                revertString: "StillLocked()"
            }),
            TestAction({
                action: Actions.Withdraw,
                user: user1,
                depositId: 1,
                nftBoost: 0.5e18,
                timeTravel: harvester.TWO_WEEKS(),
                requestRewards: 0,
                withdrawAmount: 1e18,
                lock: 0,
                originalDepositAmount: 1e18,
                depositAmount: 0,
                lockLpAmount: 0,
                lockedUntil: 0,
                globalDepositAmount: 0,
                globalLockLpAmount: 0,
                globalLpAmount: 0,
                globalRewardDebt: 0,
                magicTotalDeposits: 1e18,
                totalLpToken: 3.24e18,
                accMagicPerShare: 0.060606060606060606e18,
                pendingRewardsBefore: 0,
                pendingRewards: 0,
                revertString: ""
            }),
            TestAction({
                action: Actions.Deposit,
                user: user2,
                depositId: 2,
                nftBoost: 0.8e18,
                timeTravel: 0,
                requestRewards: 0.1e18,
                withdrawAmount: 0,
                lock: 2,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.8e18,
                lockedUntil: 0,
                globalDepositAmount: 2e18,
                globalLockLpAmount: 3.6e18,
                globalLpAmount: 6.48e18,
                globalRewardDebt: 0.492727272727272724e18,
                magicTotalDeposits: 2e18,
                totalLpToken: 6.48e18,
                accMagicPerShare: 0.091470258136924803e18,
                pendingRewardsBefore: 0,
                pendingRewards: 0.099999999999999999e18,
                revertString: ""
            }),
            TestAction({
                action: Actions.WithdrawAll,
                user: user2,
                depositId: 2,
                nftBoost: 0.8e18,
                timeTravel: harvester.THREE_MONTHS(),
                requestRewards: 0.1e18,
                withdrawAmount: 1e18,
                lock: 2,
                originalDepositAmount: 1e18,
                depositAmount: 1e18,
                lockLpAmount: 1.8e18,
                lockedUntil: 0,
                globalDepositAmount: 1e18,
                globalLockLpAmount: 1.8e18,
                globalLpAmount: 3.24e18,
                globalRewardDebt: 0.146363636363636365e18,
                magicTotalDeposits: 1e18,
                totalLpToken: 3.24e18,
                accMagicPerShare: 0.106902356902356901e18,
                pendingRewardsBefore: 0.099999999999999999e18,
                pendingRewards: 0.199999999999999994e18,
                revertString: ""
            }),
            TestAction({
                action: Actions.WithdrawAndHarvestAll,
                user: user2,
                depositId: 2,
                nftBoost: 0.8e18,
                timeTravel: harvester.TWO_WEEKS() + 1,
                requestRewards: 0,
                withdrawAmount: 1e18,
                lock: 2,
                originalDepositAmount: 1e18,
                depositAmount: 0,
                lockLpAmount: 0,
                lockedUntil: 0,
                globalDepositAmount: 0,
                globalLockLpAmount: 0,
                globalLpAmount: 0,
                globalRewardDebt: 0,
                magicTotalDeposits: 0,
                totalLpToken: 0,
                accMagicPerShare: 0.106902356902356901e18,
                pendingRewardsBefore: 0.199999999999999994e18,
                pendingRewards: 0,
                revertString: ""
            })
        ];

        (, uint256 timelock) = harvester.getLockBoost(testDepositCases[_index].lock);
        console2.log("block.timestamp", block.timestamp);
        console2.log("timelock", timelock);
        if (testDepositCases[_index].action == Actions.Deposit) {
            testDepositCases[_index].lockedUntil = block.timestamp + timelock;
        } else {
            uint256 len = depositTestCasesLength;
            uint256 timeTravelAdjustment;
            for (uint256 i = 0; i < len; i++) {
                timeTravelAdjustment += testDepositCases[i].timeTravel;

                if (
                    testDepositCases[i].action == Actions.Deposit &&
                    testDepositCases[i].depositId == testDepositCases[_index].depositId &&
                    testDepositCases[i].user == testDepositCases[_index].user
                ) {
                    timeTravelAdjustment = 0;
                    len = _index;
                }
            }
            console2.log("timeTravelAdjustment", timeTravelAdjustment);
            testDepositCases[_index].lockedUntil = block.timestamp + timelock - timeTravelAdjustment;
        }

        return testDepositCases[_index];
    }

    function mockForAction(TestAction memory data) public {
        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getStakingRules, (parts)), abi.encode(stakingRules));

        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getUserBoost, (data.user)), abi.encode(data.nftBoost));
        vm.mockCall(address(harvesterFactory), abi.encodeCall(IHarvesterFactory.middleman, ()), abi.encode(address(middlemanMock)));

        middlemanMock.setReward(data.requestRewards);

        assertEq(harvester.pendingRewardsAll(data.user), data.pendingRewardsBefore);

        if (data.timeTravel != 0) {
            vm.warp(block.timestamp + data.timeTravel);
        }
    }

    function doDeposit(TestAction memory data) public {
        if (data.revertString.length == 0) {
            magic.mint(data.user, data.originalDepositAmount);
            vm.prank(data.user);
            magic.approve(address(harvester), data.originalDepositAmount);

            vm.mockCall(stakingRules, abi.encodeCall(IPartsStakingRules.getAmountStaked, (data.user)), abi.encode(500));

            vm.prank(data.user);
            vm.expectCall(
                address(magic),
                abi.encodeCall(
                    IERC20.transferFrom,
                    (data.user, address(harvester), data.originalDepositAmount)
                )
            );
            vm.expectEmit(true, true, true, true);
            emit Deposit(data.user, data.depositId, data.originalDepositAmount, data.lock);
            harvester.deposit(data.originalDepositAmount, data.lock);
        } else {
            vm.prank(data.user);
            vm.expectRevert(data.revertString);
            harvester.deposit(data.originalDepositAmount, data.lock);
        }
    }

    function doWithdraw(TestAction memory data) public {
        uint256 balanceBefore = magic.balanceOf(data.user);

        if (data.revertString.length == 0) {
            vm.prank(data.user);
            vm.expectCall(address(magic), abi.encodeCall(IERC20.transfer, (data.user, data.withdrawAmount)));
            vm.expectEmit(true, true, true, true);
            emit Withdraw(data.user, data.depositId, data.withdrawAmount);
            harvester.withdrawPosition(data.depositId, data.withdrawAmount);

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter - data.withdrawAmount, balanceBefore);
        } else {
            vm.prank(data.user);
            vm.expectRevert(data.revertString);
            harvester.withdrawPosition(data.depositId, data.withdrawAmount);

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter, balanceBefore);
        }
    }

    function doWithdrawAll(TestAction memory data) public {
        uint256 balanceBefore = magic.balanceOf(data.user);

        if (data.revertString.length == 0) {
            vm.prank(data.user);
            harvester.withdrawAll();

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter - data.withdrawAmount, balanceBefore);
        } else {
            vm.prank(data.user);
            vm.expectRevert(data.revertString);
            harvester.withdrawAll();

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter, balanceBefore);
        }
    }

    function doHarvest(TestAction memory data) public {
        if (data.revertString.length == 0) {
            vm.prank(data.user);
            vm.expectCall(address(magic), abi.encodeCall(IERC20.transfer, (data.user, data.pendingRewardsBefore)));
            vm.expectEmit(true, true, true, true);
            emit Harvest(data.user, data.pendingRewardsBefore);
            harvester.harvestAll();
        } else {
            vm.prank(data.user);
            vm.expectRevert(data.revertString);
            harvester.harvestAll();
        }
    }

    function doWithdrawAndHarvest(TestAction memory data) public {
        uint256 balanceBefore = magic.balanceOf(data.user);

        if (data.revertString.length == 0) {
            vm.prank(data.user);
            harvester.withdrawAndHarvestPosition(data.depositId, data.withdrawAmount);

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter - data.withdrawAmount - data.pendingRewards, balanceBefore);
        } else {
            vm.prank(data.user);
            vm.expectRevert(data.revertString);
            harvester.withdrawAndHarvestPosition(data.depositId, data.withdrawAmount);

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter, balanceBefore);
        }
    }

    function doWithdrawAndHarvestAll(TestAction memory data) public {
        uint256 balanceBefore = magic.balanceOf(data.user);

        if (data.revertString.length == 0) {
            vm.prank(data.user);
            harvester.withdrawAndHarvestAll();

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter - data.withdrawAmount - data.pendingRewardsBefore, balanceBefore);
        } else {
            vm.prank(data.user);
            vm.expectRevert(data.revertString);
            harvester.withdrawAndHarvestAll();

            uint256 balanceAfter = magic.balanceOf(data.user);
            assertEq(balanceAfter, balanceBefore);
        }
    }

    function checkState(TestAction memory data) public {
        assertEq(harvester.magicTotalDeposits(), data.magicTotalDeposits);
        assertEq(harvester.totalLpToken(), data.totalLpToken);
        assertEq(harvester.accMagicPerShare(), data.accMagicPerShare);
        assertEq(harvester.pendingRewardsAll(data.user), data.pendingRewards);

        (
            uint256 originalDepositAmount,
            uint256 depositAmount,
            uint256 lockLpAmount,
            uint256 lockedUntil,
            uint256 vestingLastUpdate,
            uint256 lock
        ) = harvester.userInfo(data.user, data.depositId);

        assertEq(originalDepositAmount, data.originalDepositAmount);
        assertEq(depositAmount, data.depositAmount);
        assertEq(lockLpAmount, data.lockLpAmount);
        assertEq(lockedUntil, data.lockedUntil);
        if (data.action == Actions.Deposit) {
            assertEq(vestingLastUpdate, data.lockedUntil);
        }
        assertEq(uint256(lock), uint256(data.lock));

        (
            uint256 globalDepositAmount,
            uint256 globalLockLpAmount,
            uint256 globalLpAmount,
            int256 globalRewardDebt
        ) = harvester.getUserGlobalDeposit(data.user);

        assertEq(globalDepositAmount, data.globalDepositAmount);
        assertEq(globalLockLpAmount, data.globalLockLpAmount);
        assertEq(globalLpAmount, data.globalLpAmount);
        assertEq(globalRewardDebt, data.globalRewardDebt);
    }

    function test_depositWithdrawHarvestScenarios() public {
        for (uint256 i = 0; i < depositTestCasesLength; i++) {
            console2.log("TEST CASE:", i);

            TestAction memory data = getTestAction(i);

            mockForAction(data);

            if (data.action == Actions.Deposit) {
                doDeposit(data);
            } else if (data.action == Actions.Withdraw) {
                doWithdraw(data);
            } else if (data.action == Actions.WithdrawAll) {
                doWithdrawAll(data);
            } else if (data.action == Actions.Harvest) {
                doHarvest(data);
            } else if (data.action == Actions.WithdrawAndHarvest) {
                doWithdrawAndHarvest(data);
            } else if (data.action == Actions.WithdrawAndHarvestAll) {
                doWithdrawAndHarvestAll(data);
            }

            checkState(data);
        }
    }

    function test_depositDisabledTimelock() public {
        TestAction memory data = getTestAction(0);

        vm.prank(admin);
        harvester.disableTimelockOption(data.lock);

        mockForAction(data);

        magic.mint(data.user, data.originalDepositAmount);
        vm.prank(data.user);
        magic.approve(address(harvester), data.originalDepositAmount);

        vm.mockCall(stakingRules, abi.encodeCall(IPartsStakingRules.getAmountStaked, (data.user)), abi.encode(500));

        vm.prank(data.user);
        vm.expectRevert("Invalid value or disabled timelock");
        harvester.deposit(data.originalDepositAmount, data.lock);

        vm.prank(data.user);
        vm.expectRevert("Invalid value or disabled timelock");
        harvester.deposit(data.originalDepositAmount, 9999999);

        vm.prank(admin);
        harvester.enableTimelockOption(data.lock);

        doDeposit(data);
        checkState(data);
    }

    function test_calcualteVestedPrincipal() public {
        uint256 originalDepositAmount;
        uint256 lockedUntil;
        uint256 lock;

        TestAction memory data0 = getTestAction(0);
        mockForAction(data0);
        doDeposit(data0);

        ( originalDepositAmount,,, lockedUntil,, lock ) = harvester.userInfo(data0.user, data0.depositId);

        assertEq(harvester.calcualteVestedPrincipal(data0.user, data0.depositId), 0);

        vm.warp(lockedUntil);

        assertEq(harvester.calcualteVestedPrincipal(data0.user, data0.depositId), originalDepositAmount);

        TestAction memory data1 = getTestAction(1);
        mockForAction(data1);
        doDeposit(data1);

        ( originalDepositAmount,,, lockedUntil,, lock ) = harvester.userInfo(data1.user, data1.depositId);

        assertEq(harvester.calcualteVestedPrincipal(data1.user, data1.depositId), 0);

        uint256 vestingTime = harvester.getVestingTime(lock);
        uint256 vestingBegin = lockedUntil;

        vm.warp(vestingBegin);

        assertEq(harvester.calcualteVestedPrincipal(data1.user, data1.depositId), 0);

        uint256 quaterVestingTime = vestingTime / 4;
        uint256 quaterDepositAmount = originalDepositAmount / 4;

        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + quaterVestingTime);

            uint256 vestedAmount = harvester.calcualteVestedPrincipal(data1.user, data1.depositId);

            assertEq(vestedAmount, quaterDepositAmount + quaterDepositAmount * i);
        }
    }

    function test_updateNftBoost() public {
        TestAction memory data0 = getTestAction(0);
        TestAction memory data1 = getTestAction(1);
        mockForAction(data0);
        mockForAction(data1);
        doDeposit(data0);
        doDeposit(data1);

        (
            uint256 globalDepositAmount,
            uint256 globalLockLpAmount,
            uint256 globalLpAmount,
            int256 globalRewardDebt
        ) = harvester.getUserGlobalDeposit(data1.user);

        assertEq(globalDepositAmount, data1.globalDepositAmount);
        assertEq(globalLockLpAmount, data1.globalLockLpAmount);
        assertEq(globalLpAmount, data1.globalLpAmount);
        assertEq(globalRewardDebt, data1.globalRewardDebt);

        uint256 newUserBoost = 2.5e18;
        vm.mockCall(nftHandler, abi.encodeCall(INftHandler.getUserBoost, (data1.user)), abi.encode(newUserBoost));

        harvester.updateNftBoost(data1.user);

        (
            globalDepositAmount,
            globalLockLpAmount,
            globalLpAmount,
            globalRewardDebt
        ) = harvester.getUserGlobalDeposit(data1.user);

        uint256 newGlobalLpAmount = globalLockLpAmount + globalLockLpAmount * newUserBoost / 1e18;
        uint256 globalLpDiff = newGlobalLpAmount - data1.globalLpAmount;
        uint256 newGlobalRewardDebt = uint256(data1.globalRewardDebt) + globalLpDiff * data1.accMagicPerShare / 1e18;

        assertEq(globalDepositAmount, data1.globalDepositAmount);
        assertEq(globalLockLpAmount, data1.globalLockLpAmount);
        assertEq(globalLpAmount, newGlobalLpAmount);
        assertEq(uint256(globalRewardDebt), newGlobalRewardDebt);
    }

    function test_pendingRewardsAll() public {
        TestAction memory data = getTestAction(1);

        mockForAction(data);
        doDeposit(data);

        assertEq(harvester.pendingRewardsAll(data.user), data.pendingRewards);

        uint256 newPendingRewards = 1e18;

        vm.mockCall(address(harvesterFactory), abi.encodeCall(IHarvesterFactory.middleman, ()), abi.encode(middleman));
        vm.mockCall(middleman, abi.encodeCall(IMiddleman.getPendingRewards, (address(harvester))), abi.encode(newPendingRewards));

        assertEq(harvester.pendingRewardsAll(data.user), newPendingRewards - 1);

        vm.mockCall(middleman, abi.encodeCall(IMiddleman.getPendingRewards, (address(harvester))), abi.encode(newPendingRewards * 2));

        assertEq(harvester.pendingRewardsAll(data.user), (newPendingRewards - 1) * 2);
    }

    function test_setNftHandler() public {
        assertEq(address(harvester.nftHandler()), nftHandler);

        INftHandler newNftHandler = INftHandler(address(76e18));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.setNftHandler(newNftHandler);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit NftHandler(newNftHandler);
        harvester.setNftHandler(newNftHandler);

        assertEq(address(harvester.nftHandler()), address(newNftHandler));
    }

    function test_setDepositCapPerWallet() public {
        (address initParts, uint256 initCapPerPart) = harvester.depositCapPerWallet();
        assertEq(initParts, initDepositCapPerWallet.parts);
        assertEq(initCapPerPart, initDepositCapPerWallet.capPerPart);

        IHarvester.CapConfig memory newDepositCapPerWallet = IHarvester.CapConfig({
            parts: parts,
            capPerPart: 1e18
        });

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.setDepositCapPerWallet(newDepositCapPerWallet);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit DepositCapPerWallet(newDepositCapPerWallet);
        harvester.setDepositCapPerWallet(newDepositCapPerWallet);

        (address newParts, uint256 newCapPerPart) = harvester.depositCapPerWallet();
        assertEq(newParts, newDepositCapPerWallet.parts);
        assertEq(newCapPerPart, newDepositCapPerWallet.capPerPart);
    }

    function test_setTotalDepositCap() public {
        assertEq(harvester.totalDepositCap(), initTotalDepositCap);

        uint256 newTotalDepositCap = 11e18;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.setTotalDepositCap(newTotalDepositCap);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TotalDepositCap(newTotalDepositCap);
        harvester.setTotalDepositCap(newTotalDepositCap);

        assertEq(harvester.totalDepositCap(), newTotalDepositCap);
    }

    function test_setUnlockAll() public {
        assertFalse(harvester.unlockAll());

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.setUnlockAll(true);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit UnlockAll(true);
        harvester.setUnlockAll(true);

        assertTrue(harvester.unlockAll());
    }

    function test_addTimelockOption() public {
        IHarvester.Timelock memory newTimelockOption = IHarvester.Timelock(0.99e18, harvester.TWO_WEEKS(), 0, true);

        uint256[] memory ids = harvester.getTimelockOptionsIds();

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.addTimelockOption(newTimelockOption);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TimelockOption(newTimelockOption, ids.length);
        harvester.addTimelockOption(newTimelockOption);

        (
            uint256 boost,
            uint256 timelock,
            uint256 vesting,
            bool enabled
        ) = harvester.timelockOptions(ids.length);
        uint256[] memory newIds = harvester.getTimelockOptionsIds();

        assertEq(newIds.length, ids.length + 1);
        assertEq(boost, newTimelockOption.boost);
        assertEq(timelock, newTimelockOption.timelock);
        assertEq(vesting, newTimelockOption.vesting);
        assertEq(enabled, newTimelockOption.enabled);
    }

    function test_enableTimelockOption() public {
        uint256 id = 0;

        vm.prank(admin);
        harvester.disableTimelockOption(id);

        (
            uint256 boost,
            uint256 timelock,
            uint256 vesting,
            bool enabled
        ) = harvester.timelockOptions(id);

        assertFalse(enabled);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.enableTimelockOption(id);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TimelockOptionEnabled(IHarvester.Timelock(boost, timelock, vesting, !enabled), id);
        harvester.enableTimelockOption(id);

        (,,, enabled) = harvester.timelockOptions(id);

        assertTrue(enabled);
    }

    function test_disableTimelockOption() public {
        uint256 id = 0;

        (
            uint256 boost,
            uint256 timelock,
            uint256 vesting,
            bool enabled
        ) = harvester.timelockOptions(id);

        assertTrue(enabled);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvester.HARVESTER_ADMIN());
        vm.expectRevert(errorMsg);
        harvester.disableTimelockOption(id);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TimelockOptionDisabled(IHarvester.Timelock(boost, timelock, vesting, !enabled), id);
        harvester.disableTimelockOption(id);

        (,,, enabled) = harvester.timelockOptions(id);

        assertFalse(enabled);
    }
}

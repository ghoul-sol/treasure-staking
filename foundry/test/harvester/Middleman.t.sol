pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/ERC20Mintable.sol";

import "contracts/harvester/Middleman.sol";

contract MiddlemanTest is TestUtils {
    Middleman public middleman;

    address public magic;

    address public admin;
    address public masterOfCoin;
    address public harvesterFactory;
    address public atlasMine;
    address public corruptionToken;

    address[] public allHarvesters;

    uint256 public atlasMineBoost;

    address[] public excludedAddresses;

    event RewardsPaid(address indexed stream, uint256 rewardsPaid, uint256 rewardsPaidInTotal);
    event AddExcludedAddress(address addr);
    event RemoveExcludedAddress(address addr);
    event HarvesterFactory(IHarvesterFactory harvesterFactory);
    event MasterOfCoin(IMasterOfCoin masterOfCoin);
    event AtlasMineBoost(uint256 atlasMineBoost);
    event CorruptionNegativeBoostMatrix(uint256[][] _corruptionNegativeBoostMatrix);

    function setUp() public {
        magic = address(420);
        // workaround for ERC20's code check
        vm.etch(magic, bytes("34567876543456787654"));
        vm.label(magic, "magic");

        admin = address(111);
        vm.label(admin, "admin");
        masterOfCoin = address(112);
        vm.label(masterOfCoin, "masterOfCoin");
        harvesterFactory = address(113);
        vm.label(harvesterFactory, "harvesterFactory");
        atlasMine = address(114);
        vm.label(atlasMine, "atlasMine");
        corruptionToken = address(115);
        vm.label(corruptionToken, "corruptionToken");



        for (uint256 i = 0; i < 3; i++) {
            address harvesterAddress = address(uint160(900+i));
            allHarvesters.push(harvesterAddress);

            vm.label(allHarvesters[i], "allHarvesters[i]");
        }

        atlasMineBoost = 8e18;

        middleman = new Middleman(
            admin,
            IMasterOfCoin(masterOfCoin),
            IHarvesterFactory(harvesterFactory),
            atlasMine,
            atlasMineBoost,
            IERC20(corruptionToken)
        );
    }

    function mockGetUtilization(
        address _harvester,
        uint256 _totalSupply,
        uint256 _magicTotalDeposits,
        uint256 _excludedAddrBal,
        uint256 _harvesterBal
    ) public {
        vm.mockCall(address(harvesterFactory), abi.encodeCall(IHarvesterFactory.magic, ()), abi.encode(magic));
        vm.mockCall(magic, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(_totalSupply));
        vm.mockCall(_harvester, abi.encodeCall(IHarvester.magicTotalDeposits, ()), abi.encode(_magicTotalDeposits));

        address[] memory excluded = middleman.getExcludedAddresses();

        for (uint256 i = 0; i < excluded.length; i++) {
            vm.mockCall(magic, abi.encodeCall(IERC20.balanceOf, (excluded[i])), abi.encode(_excludedAddrBal));
        }

        vm.mockCall(magic, abi.encodeCall(IERC20.balanceOf, (_harvester)), abi.encode(_harvesterBal));
    }

    function test_getUtilization() public {
        address harvester = allHarvesters[0];
        uint256 totalSupply = 10000;
        uint256 magicTotalDeposits = 5000;
        uint256 excludedAddrBal = 100;
        uint256 harvesterBal = magicTotalDeposits + 2000;

        mockGetUtilization(harvester, totalSupply, magicTotalDeposits, excludedAddrBal, harvesterBal);

        assertEq(middleman.getUtilization(harvester), 0.625e18);

        vm.prank(admin);
        middleman.addExcludedAddress(address(10));

        mockGetUtilization(harvester, totalSupply, magicTotalDeposits, excludedAddrBal, harvesterBal);

        assertEq(middleman.getUtilization(harvester), 0.632911392405063291e18);
    }

    function test_getUtilizationBoost() public {
        address harvester = allHarvesters[0];
        uint256 totalSupply = 10000;
        uint256 magicTotalDeposits;
        uint256 excludedAddrBal = 0;
        uint256 harvesterBal = magicTotalDeposits;

        uint256[2][14] memory testCases = [
            [uint256(10000), uint256(1e18)],
            [uint256(9000), uint256(1e18)],
            [uint256(8000), uint256(1e18)],
            [uint256(7999), uint256(0.9e18)],
            [uint256(7000), uint256(0.9e18)],
            [uint256(6999), uint256(0.8e18)],
            [uint256(6000), uint256(0.8e18)],
            [uint256(5999), uint256(0.7e18)],
            [uint256(5000), uint256(0.7e18)],
            [uint256(4999), uint256(0.6e18)],
            [uint256(4000), uint256(0.6e18)],
            [uint256(3999), uint256(0.5e18)],
            [uint256(3000), uint256(0.5e18)],
            [uint256(2999), uint256(0)]
        ];

        for (uint256 i = 0; i < testCases.length; i++) {
            magicTotalDeposits = testCases[i][0];
            harvesterBal = magicTotalDeposits;
            uint256 boost = testCases[i][1];

            mockGetUtilization(harvester, totalSupply, magicTotalDeposits, excludedAddrBal, harvesterBal);

            assertEq(middleman.getUtilizationBoost(harvester), boost);
        }
    }

    function mockGetCorruptionNegativeBoost(address _corruptionToken, address _harvester, uint256 _harvesterBal) public {
        vm.mockCall(_corruptionToken, abi.encodeCall(IERC20.balanceOf, (_harvester)), abi.encode(_harvesterBal));
    }

    function test_getCorruptionNegativeBoost() public {
        address harvester = allHarvesters[0];

        uint256[2][13] memory testCases = [
            [uint256(60_001e18), uint256(0.4e18)],
            [uint256(60_000e18), uint256(0.5e18)],
            [uint256(50_001e18), uint256(0.5e18)],
            [uint256(50_000e18), uint256(0.6e18)],
            [uint256(40_001e18), uint256(0.6e18)],
            [uint256(40_000e18), uint256(0.7e18)],
            [uint256(30_001e18), uint256(0.7e18)],
            [uint256(30_000e18), uint256(0.8e18)],
            [uint256(20_001e18), uint256(0.8e18)],
            [uint256(20_000e18), uint256(0.9e18)],
            [uint256(10_001e18), uint256(0.9e18)],
            [uint256(10_000e18), uint256(1e18)],
            [uint256(0), uint256(1e18)]
        ];

        for (uint256 i = 0; i < testCases.length; i++) {
            uint256 harvesterBal = testCases[i][0];
            uint256 boost = testCases[i][1];

            mockGetCorruptionNegativeBoost(corruptionToken, harvester, harvesterBal);

            assertEq(middleman.getCorruptionNegativeBoost(harvester), boost);
        }
    }

    function mockGetHarvesterEmissionsShare(
        address _harvester,
        uint256 _harvesterTotalBoost,
        uint256 _totalSupply,
        uint256 _magicTotalDeposits,
        uint256 _excludedAddrBal,
        uint256 _harvesterBal,
        uint256 _corruptionBalance
    ) public {
        address nftHandler = address(uint160(_harvester) + 99);
        vm.mockCall(_harvester, abi.encodeCall(IHarvester.nftHandler, ()), abi.encode(nftHandler));
        vm.mockCall(
            nftHandler,
            abi.encodeCall(INftHandler.getHarvesterTotalBoost, ()),
            abi.encode(_harvesterTotalBoost)
        );

        mockGetUtilization(_harvester, _totalSupply, _magicTotalDeposits, _excludedAddrBal, _harvesterBal);

        mockGetCorruptionNegativeBoost(corruptionToken, _harvester, _corruptionBalance);
    }

    struct EmissionsShareTest {
        uint256 harvesterTotalBoost;
        uint256 totalSupply;
        uint256 magicTotalDeposits;
        uint256 excludedAddrBal;
        uint256 harvesterBal;
        uint256 expectedUtilizationBoost;
        uint256 corruptionBalance;
        uint256 expectedCorruptionNegativeBoost;
        uint256 expectedHarvesterEmissionsShare;
    }

    // workaround for "UnimplementedFeatureError: Copying of type struct memory to storage not yet supported."
    uint256 public constant emissionsTestCasesLength = 3;

    function getEmissionsTestCase(uint256 _index) public pure returns (EmissionsShareTest memory) {
        EmissionsShareTest[emissionsTestCasesLength] memory emissionsTestCases = [
            // TODO: add more test cases
            EmissionsShareTest({
                harvesterTotalBoost: 2e18,
                totalSupply: 10000,
                magicTotalDeposits: 10000,
                excludedAddrBal: 0,
                harvesterBal: 10000,
                expectedUtilizationBoost: 1e18,
                corruptionBalance: 0,
                expectedCorruptionNegativeBoost: 1e18,
                expectedHarvesterEmissionsShare: 2e18
            }),
            EmissionsShareTest({
                harvesterTotalBoost: 4e18,
                totalSupply: 10000,
                magicTotalDeposits: 3500,
                excludedAddrBal: 0,
                harvesterBal: 3500,
                expectedUtilizationBoost: 0.5e18,
                corruptionBalance: 0,
                expectedCorruptionNegativeBoost: 1e18,
                expectedHarvesterEmissionsShare: 2e18
            }),
            EmissionsShareTest({
                harvesterTotalBoost: 4e18,
                totalSupply: 10000,
                magicTotalDeposits: 10000,
                excludedAddrBal: 0,
                harvesterBal: 10000,
                expectedUtilizationBoost: 1e18,
                corruptionBalance: 0,
                expectedCorruptionNegativeBoost: 1e18,
                expectedHarvesterEmissionsShare: 4e18
            })
        ];

        return emissionsTestCases[_index];
    }

    function test_getHarvesterEmissionsShare() public {
        address harvester = allHarvesters[0];

        for (uint256 i = 0; i < emissionsTestCasesLength; i++) {
            EmissionsShareTest memory data = getEmissionsTestCase(i);

            mockGetHarvesterEmissionsShare(
                harvester,
                data.harvesterTotalBoost,
                data.totalSupply,
                data.magicTotalDeposits,
                data.excludedAddrBal,
                data.harvesterBal,
                data.corruptionBalance
            );

            assertEq(middleman.getUtilizationBoost(harvester), data.expectedUtilizationBoost);
            assertEq(middleman.getCorruptionNegativeBoost(harvester), data.expectedCorruptionNegativeBoost);
            assertEq(middleman.getHarvesterEmissionsShare(harvester), data.expectedHarvesterEmissionsShare);
        }
    }

    function setupDistributeRewards(uint256 _rewards) public {
        vm.mockCall(address(masterOfCoin), abi.encodeCall(IMasterOfCoin.requestRewards, ()), abi.encode(_rewards));

        vm.mockCall(
            address(harvesterFactory),
            abi.encodeCall(IHarvesterFactory.getAllHarvesters, ()),
            abi.encode(allHarvesters)
        );

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            EmissionsShareTest memory data = getEmissionsTestCase(i);

            mockGetHarvesterEmissionsShare(
                allHarvesters[i],
                data.harvesterTotalBoost,
                data.totalSupply,
                data.magicTotalDeposits,
                data.excludedAddrBal,
                data.harvesterBal,
                data.corruptionBalance
            );
        }
    }

    function test_distributeRewards() public {
        uint256 unpaid;
        uint256 rewards = 10000;

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            (unpaid, ) = middleman.rewardsBalance(allHarvesters[i]);
            assertEq(unpaid, 0);
        }

        setupDistributeRewards(rewards);

        middleman.distributeRewards();

        (unpaid, ) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 5000);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[0]);
        assertEq(unpaid, 1250);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[1]);
        assertEq(unpaid, 1250);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[2]);
        assertEq(unpaid, 2500);

        vm.prank(admin);
        middleman.setAtlasMineBoost(0);

        middleman.distributeRewards();

        (unpaid, ) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 5000);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[0]);
        assertEq(unpaid, 1250);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[1]);
        assertEq(unpaid, 1250);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[2]);
        assertEq(unpaid, 2500);

        vm.warp(block.timestamp + 1);
        middleman.distributeRewards();

        (unpaid, ) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 5000);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[0]);
        assertEq(unpaid, 3750);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[1]);
        assertEq(unpaid, 3750);
        (unpaid, ) = middleman.rewardsBalance(allHarvesters[2]);
        assertEq(unpaid, 7500);
    }

    function test_requestRewards() public {
        uint256 paid;
        uint256 unpaid;
        uint256 rewardsPaid;
        uint256 rewards = 10000;
        uint256[4] memory expectedRewards = [uint256(5000), 1250, 1250, 2500];

        setupDistributeRewards(rewards);

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            (unpaid, paid) = middleman.rewardsBalance(allHarvesters[i]);
            assertEq(unpaid, 0);
            assertEq(paid, 0);

            vm.mockCall(
                magic,
                abi.encodeCall(IERC20.transfer, (allHarvesters[i], expectedRewards[i + 1])),
                abi.encode(true)
            );
        }

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 0);
        assertEq(paid, 0);

        vm.mockCall(
            magic,
            abi.encodeCall(IERC20.transfer, (atlasMine, expectedRewards[0])),
            abi.encode(true)
        );

        middleman.distributeRewards();

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            (unpaid, paid) = middleman.rewardsBalance(allHarvesters[i]);
            assertEq(unpaid, expectedRewards[i + 1]);
            assertEq(paid, 0);
        }

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, expectedRewards[0]);
        assertEq(paid, 0);

        vm.prank(atlasMine);
        vm.expectCall(magic, abi.encodeCall(IERC20.transfer, (atlasMine, expectedRewards[0])));
        vm.expectEmit(true, true, true, true);
        emit RewardsPaid(atlasMine, expectedRewards[0], expectedRewards[0]);
        rewardsPaid = middleman.requestRewards();
        assertEq(rewardsPaid, expectedRewards[0]);

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 0);
        assertEq(paid, expectedRewards[0]);

        vm.prank(atlasMine);
        rewardsPaid = middleman.requestRewards();
        assertEq(rewardsPaid, 0);

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 0);
        assertEq(paid, expectedRewards[0]);

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            address harvester = allHarvesters[i];
            uint256 expectedReward = expectedRewards[i + 1];
            uint256 totalReward = expectedReward;

            vm.prank(harvester);
            vm.expectCall(magic, abi.encodeCall(IERC20.transfer, (harvester, expectedReward)));
            vm.expectEmit(true, true, true, true);
            emit RewardsPaid(harvester, expectedReward, totalReward);
            rewardsPaid = middleman.requestRewards();
            assertEq(rewardsPaid, expectedReward);

            (unpaid, paid) = middleman.rewardsBalance(harvester);
            assertEq(unpaid, 0);
            assertEq(paid, expectedReward);

            vm.prank(harvester);
            rewardsPaid = middleman.requestRewards();
            assertEq(rewardsPaid, 0);

            (unpaid, paid) = middleman.rewardsBalance(harvester);
            assertEq(unpaid, 0);
            assertEq(paid, expectedReward);
        }

        vm.warp(block.timestamp + 1);
        middleman.distributeRewards();

        vm.warp(block.timestamp + 1);
        middleman.distributeRewards();

        for (uint256 i = 0; i < allHarvesters.length; i++) {
            address harvester = allHarvesters[i];
            uint256 expectedReward = expectedRewards[i + 1] * 2;
            uint256 totalReward = expectedRewards[i + 1] * 3;

            vm.mockCall(magic, abi.encodeCall(IERC20.transfer, (harvester, expectedReward)), abi.encode(true));

            vm.prank(harvester);
            vm.expectCall(magic, abi.encodeCall(IERC20.transfer, (harvester, expectedReward)));
            vm.expectEmit(true, true, true, true);
            emit RewardsPaid(harvester, expectedReward, totalReward);
            rewardsPaid = middleman.requestRewards();
            assertEq(rewardsPaid, expectedReward);

            (unpaid, paid) = middleman.rewardsBalance(harvester);
            assertEq(unpaid, 0);
            assertEq(paid, totalReward);

            vm.prank(harvester);
            rewardsPaid = middleman.requestRewards();
            assertEq(rewardsPaid, 0);

            (unpaid, paid) = middleman.rewardsBalance(harvester);
            assertEq(unpaid, 0);
            assertEq(paid, totalReward);
        }

        vm.warp(block.timestamp + 1);
        middleman.distributeRewards();

        uint256 atlasPaidReward = expectedRewards[0];
        uint256 atlasExpectedReward = expectedRewards[0] * 3;
        uint256 atlasTotalReward = expectedRewards[0] * 4;

        vm.mockCall(magic, abi.encodeCall(IERC20.transfer, (atlasMine, atlasExpectedReward)), abi.encode(true));

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, atlasExpectedReward);
        assertEq(paid, atlasPaidReward);

        vm.prank(atlasMine);
        vm.expectCall(magic, abi.encodeCall(IERC20.transfer, (atlasMine, atlasExpectedReward)));
        vm.expectEmit(true, true, true, true);
        emit RewardsPaid(atlasMine, atlasExpectedReward, atlasTotalReward);
        rewardsPaid = middleman.requestRewards();
        assertEq(rewardsPaid, atlasExpectedReward);

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 0);
        assertEq(paid, atlasTotalReward);

        vm.prank(atlasMine);
        rewardsPaid = middleman.requestRewards();
        assertEq(rewardsPaid, 0);

        (unpaid, paid) = middleman.rewardsBalance(atlasMine);
        assertEq(unpaid, 0);
        assertEq(paid, atlasTotalReward);

        vm.prank(address(1234567890));
        rewardsPaid = middleman.requestRewards();
        assertEq(rewardsPaid, 0);
    }

    function test_addExcludedAddress() public {
        assertEq(middleman.getExcludedAddresses().length, 0);

        address excludedAddress = address(76);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), middleman.MIDDLEMAN_ADMIN());
        vm.expectRevert(errorMsg);
        middleman.addExcludedAddress(excludedAddress);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit AddExcludedAddress(excludedAddress);
        middleman.addExcludedAddress(excludedAddress);

        assertEq(middleman.getExcludedAddresses().length, 1);
        assertEq(middleman.getExcludedAddresses()[0], excludedAddress);

        vm.prank(admin);
        vm.expectRevert("Address already excluded");
        middleman.addExcludedAddress(excludedAddress);
    }

    function test_removeExcludedAddress() public {
        address excludedAddress1 = address(76);
        address excludedAddress2 = address(765);

        vm.prank(admin);
        middleman.addExcludedAddress(excludedAddress1);

        vm.prank(admin);
        middleman.addExcludedAddress(excludedAddress2);

        assertEq(middleman.getExcludedAddresses().length, 2);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), middleman.MIDDLEMAN_ADMIN());
        vm.expectRevert(errorMsg);
        middleman.removeExcludedAddress(excludedAddress1);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RemoveExcludedAddress(excludedAddress1);
        middleman.removeExcludedAddress(excludedAddress1);

        assertEq(middleman.getExcludedAddresses().length, 1);
        assertEq(middleman.getExcludedAddresses()[0], excludedAddress2);

        vm.prank(admin);
        vm.expectRevert("Address is not excluded");
        middleman.removeExcludedAddress(excludedAddress1);

        vm.prank(admin);
        middleman.addExcludedAddress(excludedAddress1);

        assertEq(middleman.getExcludedAddresses().length, 2);
        assertEq(middleman.getExcludedAddresses()[0], excludedAddress2);
        assertEq(middleman.getExcludedAddresses()[1], excludedAddress1);
    }

    function test_getExcludedAddresses() public {
        vm.startPrank(admin);

        for (uint256 i = 0; i < 25; i++) {
            address excludedAddr = address(uint160(i + 55));

            excludedAddresses.push(excludedAddr);
            middleman.addExcludedAddress(excludedAddr);
            assertAddressArrayEq(middleman.getExcludedAddresses(), excludedAddresses);

            if (i % 2 == 0) {
                address removeAddr = excludedAddresses[excludedAddresses.length - 1];
                excludedAddresses.pop();
                middleman.removeExcludedAddress(removeAddr);
                assertAddressArrayEq(middleman.getExcludedAddresses(), excludedAddresses);
            }
        }

        vm.stopPrank();
    }

    function test_setHarvesterFactory() public {
        assertEq(address(middleman.harvesterFactory()), harvesterFactory);

        IHarvesterFactory newHarvesterFactory = IHarvesterFactory(address(76));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), middleman.MIDDLEMAN_ADMIN());
        vm.expectRevert(errorMsg);
        middleman.setHarvesterFactory(newHarvesterFactory);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit HarvesterFactory(newHarvesterFactory);
        middleman.setHarvesterFactory(newHarvesterFactory);

        assertEq(address(middleman.harvesterFactory()), address(newHarvesterFactory));
    }

    function test_setMasterOfCoin() public {
        assertEq(address(middleman.masterOfCoin()), masterOfCoin);

        IMasterOfCoin newMasterOfCoin = IMasterOfCoin(address(76));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), middleman.MIDDLEMAN_ADMIN());
        vm.expectRevert(errorMsg);
        middleman.setMasterOfCoin(newMasterOfCoin);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MasterOfCoin(newMasterOfCoin);
        middleman.setMasterOfCoin(newMasterOfCoin);

        assertEq(address(middleman.masterOfCoin()), address(newMasterOfCoin));
    }

    uint256[][] public oldCorruptionNegativeBoostMatrix = [
        [uint256(60_000e18), uint256(0.4e18)],
        [uint256(50_000e18), uint256(0.5e18)],
        [uint256(40_000e18), uint256(0.6e18)],
        [uint256(30_000e18), uint256(0.7e18)],
        [uint256(20_000e18), uint256(0.8e18)],
        [uint256(10_000e18), uint256(0.9e18)]
    ];

    function test_getCorruptionNegativeBoostMatrix() public {
        assertMatrixEq(middleman.getCorruptionNegativeBoostMatrix(), oldCorruptionNegativeBoostMatrix);
    }

    uint256[][] public newCorruptionNegativeBoostMatrix = [
        [uint256(6_000e18), uint256(0.04e18)],
        [uint256(5_000e18), uint256(0.05e18)],
        [uint256(4_000e18), uint256(0.06e18)],
        [uint256(3_000e18), uint256(0.07e18)],
        [uint256(2_000e18), uint256(0.08e18)],
        [uint256(1_000e18), uint256(0.09e18)]
    ];

    function test_setCorruptionNegativeBoostMatrix() public {
        assertMatrixEq(middleman.getCorruptionNegativeBoostMatrix(), oldCorruptionNegativeBoostMatrix);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), middleman.MIDDLEMAN_ADMIN());
        vm.expectRevert(errorMsg);
        middleman.setCorruptionNegativeBoostMatrix(newCorruptionNegativeBoostMatrix);
        assertMatrixEq(middleman.getCorruptionNegativeBoostMatrix(), oldCorruptionNegativeBoostMatrix);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit CorruptionNegativeBoostMatrix(newCorruptionNegativeBoostMatrix);
        middleman.setCorruptionNegativeBoostMatrix(newCorruptionNegativeBoostMatrix);

        assertMatrixEq(middleman.getCorruptionNegativeBoostMatrix(), newCorruptionNegativeBoostMatrix);
    }

    function test_setAtlasMineBoost() public {
        assertEq(middleman.atlasMineBoost(), atlasMineBoost);

        uint256 newAtlasMineBoost = uint256(76e18);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), middleman.MIDDLEMAN_ADMIN());
        vm.expectRevert(errorMsg);
        middleman.setAtlasMineBoost(newAtlasMineBoost);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit AtlasMineBoost(newAtlasMineBoost);
        middleman.setAtlasMineBoost(newAtlasMineBoost);

        assertEq(middleman.atlasMineBoost(), newAtlasMineBoost);
    }
}

pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/Mock.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "contracts/harvester/interfaces/INftHandler.sol";
import "contracts/harvester/interfaces/IHarvester.sol";
import 'contracts/interfaces/ILegionMetadataStore.sol';
import "contracts/harvester/rules/LegionStakingRules.sol";

contract LegionStakingRulesMock is LegionStakingRules {
    function setStaked(uint256 _staked) public {
        staked = _staked;
    }
}

contract LegionStakingRulesTest is TestUtils {
    struct TestCase {
        uint256 legionGeneration;
        uint256 legionRarity;
        uint256 boost;
        uint256 rank;
        uint256 weight;
    }

    // workaround for "UnimplementedFeatureError: Copying of type struct memory to storage not yet supported."
    uint256 public constant testCasesLength = 18;

    LegionStakingRulesMock public legionRules;

    address public admin = address(111);
    address public harvesterFactory = address(222);
    address public harvester = address(333);
    address public legionMetadataStore = address(new Mock("LegionMetadataStore"));
    uint256 public maxLegionWeight = 200e18;
    uint256 public maxStakeableTotal = 100;
    uint256 public boostFactor = 1e18;

    function setUp() public {
        address impl = address(new LegionStakingRulesMock());

        legionRules = LegionStakingRulesMock(address(new ERC1967Proxy(impl, bytes(""))));
        legionRules.init(
            admin,
            harvesterFactory,
            ILegionMetadataStore(legionMetadataStore),
            maxLegionWeight,
            maxStakeableTotal,
            boostFactor
        );

        vm.prank(harvesterFactory);
        legionRules.setNftHandler(address(this));

        vm.mockCall(address(harvester), abi.encodeCall(IHarvester.callUpdateRewards, ()), abi.encode(true));
    }

    function getTestCase(uint256 _i) public view returns (TestCase memory) {

        uint256 illegalWeight = maxLegionWeight * 1e18;
        uint256 illegalRank = 1e18;

        TestCase[testCasesLength] memory testCases = [
            // TODO: add more test cases
            // TestCase(legionGeneration, legionRarity, boost, rank, weight)
            // Genesis Legions
            TestCase(0, 0, 600e16, 4e18, 120e18), // LEGENDARY
            TestCase(0, 1, 200e16, 4e18, 40e18), // RARE
            TestCase(0, 2, 75e16, 2e18, 16e18), // SPECIAL
            TestCase(0, 3, 100e16, 3e18, 21e18), // UNCOMMON
            TestCase(0, 4, 50e16, 1.5e18, 11e18), // COMMON
            TestCase(0, 5, 0, illegalRank, illegalWeight), // RECRUIT
            // Aux Legions
            TestCase(1, 0, 0, illegalRank, illegalWeight),
            TestCase(1, 1, 25e16, 1.2e18, 5.5e18), // RARE
            TestCase(1, 2, 0, illegalRank, illegalWeight),
            TestCase(1, 3, 10e16, 1.1e18, 4e18), // UNCOMMON
            TestCase(1, 4, 5e16, 1e18, 2.5e18), // COMMON
            TestCase(1, 5, 0, illegalRank, illegalWeight),
            // Recruits
            TestCase(2, 0, 0, illegalRank, illegalWeight),
            TestCase(2, 1, 0, illegalRank, illegalWeight),
            TestCase(2, 2, 0, illegalRank, illegalWeight),
            TestCase(2, 3, 0, illegalRank, illegalWeight),
            TestCase(2, 4, 0, illegalRank, illegalWeight),
            TestCase(2, 5, 0, illegalRank, illegalWeight)
        ];

        return testCases[_i];
    }

    function getMockMetadata(uint256 _legionGeneration, uint256 _legionRarity)
        public
        pure
        returns (ILegionMetadataStore.LegionMetadata memory metadata)
    {
        metadata = ILegionMetadataStore.LegionMetadata(
            ILegionMetadataStore.LegionGeneration(_legionGeneration),
            ILegionMetadataStore.LegionClass.RECRUIT,
            ILegionMetadataStore.LegionRarity(_legionRarity),
            1,
            2,
            [0, 1, 2, 3, 4, 5]
        );
    }

    function mockMetadataCall(uint256 _tokenId, uint256 _legionGeneration, uint256 _legionRarity) public {
        vm.mockCall(
            legionMetadataStore,
            abi.encodeCall(ILegionMetadataStore.metadataForLegion, (_tokenId)),
            abi.encode(getMockMetadata(_legionGeneration, _legionRarity))
        );
    }

    function test_getUserBoost() public {
        for (uint256 i = 0; i < testCasesLength; i++) {
            TestCase memory testCase = getTestCase(i);
            uint256 tokenId = i;

            mockMetadataCall(tokenId, testCase.legionGeneration, testCase.legionRarity);

            assertEq(legionRules.getUserBoost(address(0), address(0), tokenId, 0), testCase.boost);
        }
    }

    function test_getLegionBoost() public {
        for (uint256 i = 0; i < testCasesLength; i++) {
            TestCase memory testCase = getTestCase(i);
            uint256 tokenId = i;

            mockMetadataCall(tokenId, testCase.legionGeneration, testCase.legionRarity);

            assertEq(
                legionRules.getLegionBoost(testCase.legionGeneration, testCase.legionRarity),
                testCase.boost
            );
        }
    }

    function test_getRank() public {
        for (uint256 i = 0; i < testCasesLength; i++) {
            TestCase memory testCase = getTestCase(i);
            uint256 tokenId = i;

            mockMetadataCall(tokenId, testCase.legionGeneration, testCase.legionRarity);

            assertEq(legionRules.getRank(tokenId), testCase.rank);
        }
    }

    function test_getWeight() public {
        for (uint256 i = 0; i < testCasesLength; i++) {
            TestCase memory testCase = getTestCase(i);
            uint256 tokenId = i;

            mockMetadataCall(tokenId, testCase.legionGeneration, testCase.legionRarity);

            assertEq(legionRules.getWeight(tokenId), testCase.weight);
        }
    }

    function test_getHarvesterBoost() public {

        uint256[5][15] memory testData = [
            // maxStakeableTotal, staked, totalRank, boostFactor, result
            [uint256(11), 9, 10e18, 2e18, 2955371900826446280],
            // vary maxStakeableTotal and staked
            [uint256(2400), 0, 10e18, 2e18, 1e18],
            [uint256(2400), 90, 10e18, 2e18, 1134104166666666666],
            [uint256(2400), 2400, 10e18, 2e18, 2800833333333333332],
            [uint256(1), 0, 1e18, 2e18, 1e18],
            [uint256(1), 1, 1e18, 2e18, 3e18],
            [uint256(99999), 0, 10e18, 2e18, 1e18],
            [uint256(99999), 900, 10e18, 2e18, 1032294341483600237],
            [uint256(99999), 9999, 10e18, 2e18, 1342008840122601568],
            [uint256(99999), 99999, 10e18, 2e18, 2800020000200002000],
            // vary boostFactor
            [uint256(2400), 9, 10e18, 1e18, 1007569114583333333],
            [uint256(2400), 2400, 10e18, 9e18, 9103749999999999994],
            // vary totalRank
            [uint256(2400), 2200, 1e18, 1e18, 1893795138888888888],
            [uint256(2400), 2200, 50e18, 1e18, 1896006944444444443],
            [uint256(2400), 2200, 50e19, 1e18, 1916319444444444444]
        ];

        for (uint256 i = 0; i < 1; i++) {
            vm.prank(admin);
            legionRules.setMaxStakeableTotal(uint256(testData[0][0]));
            assertEq(legionRules.maxStakeableTotal(), testData[0][0]);

            legionRules.setStaked(uint256(testData[0][1]));
            assertEq(legionRules.staked(), testData[0][1]);

            vm.prank(admin);
            legionRules.setTotalRank(uint256(testData[0][2]));
            assertEq(legionRules.totalRank(), testData[0][2]);

            vm.prank(admin);
            legionRules.setBoostFactor(uint256(testData[0][3]));
            assertEq(legionRules.boostFactor(), testData[0][3]);

            assertEq(legionRules.getHarvesterBoost(), testData[0][4]);
        }
    }

    function test_processStake(address _user, address _nft, uint256 _tokenId, uint256 _amount) public {
        // Paused
        // MaxWeightReached
        // check
        // legionRules.processStake(_user, _nft, _tokenId, _amount);
    }

    function test_processUnstake() public {

    }

    function test_setLegionMetadataStore() public {
        assertEq(address(legionRules.legionMetadataStore()), legionMetadataStore);

        ILegionMetadataStore newLegionMetadataStore = ILegionMetadataStore(address(1234));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setLegionMetadataStore(newLegionMetadataStore);
        assertEq(address(legionRules.legionMetadataStore()), legionMetadataStore);

        vm.prank(admin);
        legionRules.setLegionMetadataStore(newLegionMetadataStore);
        assertEq(address(legionRules.legionMetadataStore()), address(newLegionMetadataStore));
    }

    function test_setMaxWeight() public {
        assertEq(legionRules.maxLegionWeight(), maxLegionWeight);

        uint256 newMaxLegionWeight = 400e18;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setMaxWeight(newMaxLegionWeight);
        assertEq(legionRules.maxLegionWeight(), maxLegionWeight);

        vm.prank(admin);
        legionRules.setMaxWeight(newMaxLegionWeight);
        assertEq(legionRules.maxLegionWeight(), newMaxLegionWeight);
    }

    function test_setMaxStakeableTotal() public {
        assertEq(legionRules.maxStakeableTotal(), maxStakeableTotal);

        uint256 newMaxStakeableTotal = 500;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setMaxStakeableTotal(newMaxStakeableTotal);
        assertEq(legionRules.maxStakeableTotal(), maxStakeableTotal);

        vm.prank(admin);
        legionRules.setMaxStakeableTotal(newMaxStakeableTotal);
        assertEq(legionRules.maxStakeableTotal(), newMaxStakeableTotal);
    }

    function test_setBoostFactor() public {
        assertEq(legionRules.boostFactor(), boostFactor);

        uint256 newBoostFactor = 20e18;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setBoostFactor(newBoostFactor);
        assertEq(legionRules.boostFactor(), boostFactor);

        vm.prank(admin);
        legionRules.setBoostFactor(newBoostFactor);
        assertEq(legionRules.boostFactor(), newBoostFactor);
    }

    uint256[][] public newLegionBoostMatrix = [
        [uint256(600e16), uint256(200e16), uint256(75e16), uint256(100e16), uint256(50e16), uint256(0)],
        [uint256(600e16), uint256(200e16), uint256(75e16), uint256(100e16), uint256(50e16), uint256(0)],
        [uint256(600e16), uint256(200e16), uint256(75e16), uint256(100e16), uint256(50e16), uint256(0)]
    ];

    function test_setLegionBoostMatrix() public {
        uint256[][] memory legionBoostMatrix = legionRules.getLegionBoostMatrix();

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setLegionBoostMatrix(newLegionBoostMatrix);
        assertMatrixEq(legionRules.getLegionBoostMatrix(), legionBoostMatrix);

        vm.prank(admin);
        legionRules.setLegionBoostMatrix(newLegionBoostMatrix);
        assertMatrixEq(legionRules.getLegionBoostMatrix(), newLegionBoostMatrix);
    }

    uint256[][] public newLegionWeightMatrix = [
        [uint256(120e18), uint256(40e18), uint256(15e18), uint256(20e18), uint256(10e18), uint256(0)],
        [uint256(120e18), uint256(40e18), uint256(15e18), uint256(20e18), uint256(10e18), uint256(0)],
        [uint256(120e18), uint256(40e18), uint256(15e18), uint256(20e18), uint256(10e18), uint256(0)]
    ];

    function test_setLegionWeightMatrix() public {
        uint256[][] memory legionWeightMatrix = legionRules.getLegionWeightMatrix();

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setLegionWeightMatrix(newLegionWeightMatrix);
        assertMatrixEq(legionRules.getLegionWeightMatrix(), legionWeightMatrix);

        vm.prank(admin);
        legionRules.setLegionWeightMatrix(newLegionWeightMatrix);
        assertMatrixEq(legionRules.getLegionWeightMatrix(), newLegionWeightMatrix);
    }

    uint256[][] public newLegionRankMatrix = [
        [uint256(4e18), uint256(4e18), uint256(2e18), uint256(3e18), uint256(1e18), uint256(0)],
        [uint256(4e18), uint256(4e18), uint256(2e18), uint256(3e18), uint256(1e18), uint256(0)],
        [uint256(4e18), uint256(4e18), uint256(2e18), uint256(3e18), uint256(1e18), uint256(0)]
    ];

    function test_setLegionRankMatrix() public {
        uint256[][] memory legionRankMatrix = legionRules.getLegionRankMatrix();

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setLegionRankMatrix(newLegionRankMatrix);
        assertMatrixEq(legionRules.getLegionRankMatrix(), legionRankMatrix);

        vm.prank(admin);
        legionRules.setLegionRankMatrix(newLegionRankMatrix);
        assertMatrixEq(legionRules.getLegionRankMatrix(), newLegionRankMatrix);
    }

    function test_setTotalRank() public {
        assertEq(legionRules.totalRank(), 0);

        uint256 newTotalRank = 200000e18;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.setTotalRank(newTotalRank);
        assertEq(legionRules.totalRank(), 0);

        vm.prank(admin);
        legionRules.setTotalRank(newTotalRank);
        assertEq(legionRules.totalRank(), newTotalRank);
    }

    function test_pause() public {
        assertEq(legionRules.paused(), false);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.pause();
        assertEq(legionRules.paused(), false);

        vm.prank(admin);
        legionRules.pause();
        assertEq(legionRules.paused(), true);

        vm.prank(admin);
        vm.expectRevert(LegionStakingRules.Paused.selector);
        legionRules.pause();
    }

    function test_unpause() public {
        assertEq(legionRules.paused(), false);

        vm.prank(admin);
        legionRules.pause();
        assertEq(legionRules.paused(), true);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), legionRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        legionRules.unpause();
        assertEq(legionRules.paused(), true);

        vm.prank(admin);
        legionRules.unpause();
        assertEq(legionRules.paused(), false);

        vm.prank(admin);
        vm.expectRevert(LegionStakingRules.Unpaused.selector);
        legionRules.unpause();
    }
}

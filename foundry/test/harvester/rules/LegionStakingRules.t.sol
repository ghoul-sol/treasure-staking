pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../lib/TestUtils.sol";
import "../../../lib/Mock.sol";

import "../../../../contracts/harvester/interfaces/INftHandler.sol";
import "../../../../contracts/harvester/interfaces/IHarvester.sol";
import '../../../../contracts/interfaces/ILegionMetadataStore.sol';

import "../../../../contracts/harvester/rules/LegionStakingRules.sol";

contract LegionStakingRulesTest is Test {
    struct TestCase {
        uint256 legionGeneration;
        uint256 legionRarity;
        uint256 boost;
        uint256 rank;
        uint256 weight;
    }

    // workaround for "UnimplementedFeatureError: Copying of type struct memory to storage not yet supported."
    uint256 public constant testCasesLength = 1;

    LegionStakingRules public legionRules;

    address public admin;
    address public harvester;
    address public harvesterFactory;
    address public legionMetadataStore;
    address public nftHandler;
    uint256 public maxLegionWeight;
    uint256 public maxStakeableTotal;
    uint256 public boostFactor;

    function setUp() public {
        admin = address(111);
        harvesterFactory = address(222);

        harvester = address(new Mock("Harvester"));
        nftHandler = address(new Mock("NftHandler"));
        legionMetadataStore = address(new Mock("LegionMetadataStore"));

        maxLegionWeight = 200e18;
        maxStakeableTotal = 100;
        boostFactor = 1e18;

        legionRules = new LegionStakingRules(
            admin,
            harvesterFactory,
            ILegionMetadataStore(legionMetadataStore),
            maxLegionWeight,
            maxStakeableTotal,
            boostFactor
        );
    }

    function getTestCase(uint256 _i) public pure returns (TestCase memory) {
        TestCase[testCasesLength] memory testCases = [
            // TODO: add more test cases
            TestCase(0, 0, 600e16, 4e18, 120e18)
        ];

        return testCases[_i];
    }

    function mockMetadataCall(uint256 _tokenId, uint256 _legionGeneration, uint256 _legionRarity) public {
        ILegionMetadataStore.LegionMetadata memory metadata = ILegionMetadataStore.LegionMetadata(
            ILegionMetadataStore.LegionGeneration(_legionGeneration),
            ILegionMetadataStore.LegionClass.RECRUIT,
            ILegionMetadataStore.LegionRarity(_legionRarity),
            1,
            2,
            [0, 1, 2, 3, 4, 5]
        );

        vm.mockCall(
            legionMetadataStore,
            abi.encodeCall(ILegionMetadataStore.metadataForLegion, (_tokenId)),
            abi.encode(metadata)
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
        uint256[5][1] memory testData = [
            // TODO: add more test cases
            // maxStakeableTotal, staked, totalRank, boostFactor, result
            [uint256(11), 9, 10e18, 2e18, 2955371900826446280]
        ];

        for (uint256 i = 0; i < testData.length; i++) {
            // set maxStakeableTotal
            vm.store(address(legionRules), bytes32(uint256(3)), bytes32(testData[0][0]));
            assertEq(legionRules.maxStakeableTotal(), testData[0][0]);

            // set staked
            vm.store(address(legionRules), bytes32(uint256(2)), bytes32(testData[0][1]));
            assertEq(legionRules.staked(), testData[0][1]);

            // set totalRank
            vm.store(address(legionRules), bytes32(uint256(5)), bytes32(testData[0][2]));
            assertEq(legionRules.totalRank(), testData[0][2]);

            // set boostFactor
            vm.store(address(legionRules), bytes32(uint256(6)), bytes32(testData[0][3]));
            assertEq(legionRules.boostFactor(), testData[0][3]);

            assertEq(legionRules.getHarvesterBoost(), testData[0][4]);
        }
    }

    // function test_canStake() public {}
    // function test_canUnstake() public {}

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

    function assertMatrixEq(uint256[][] memory _matrix1, uint256[][] memory _matrix2) public {
        for (uint256 i = 0; i < _matrix1.length; i++) {
            for (uint256 j = 0; j < _matrix1[i].length; j++) {
                assertEq(_matrix1[i][j], _matrix2[i][j]);
            }
        }
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
}

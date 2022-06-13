pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/Mock.sol";
import "foundry/lib/ERC721Mintable.sol";
import "foundry/lib/ERC1155Mintable.sol";

import "forge-std/console2.sol";
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

import "contracts/harvester/interfaces/INftHandler.sol";
import "contracts/harvester/interfaces/IHarvester.sol";
import "contracts/harvester/rules/LegionStakingRules.sol";
import "contracts/harvester/rules/ExtractorStakingRules.sol";
import "contracts/harvester/NftHandler.sol";
import "./rules/LegionStakingRules.t.sol";

contract NftHandlerTest is TestUtils, ERC1155Holder {
    LegionStakingRulesTest legionTest;

    NftHandler public nftHandler;

    address public admin;
    address public harvester;
    address public harvesterFactory;

    address public legionMetadataStore;
    uint256 public maxLegionWeight;
    uint256 public maxStakeableTotal;
    uint256 public boostFactor;

    address public extractorAddress;
    uint256 public maxStakeable;
    uint256 public lifetime;

    ERC721Mintable public nftErc721;
    ERC1155Mintable public nftErc1155;
    LegionStakingRules public erc721StakingRules;
    ExtractorStakingRules public erc1155StakingRules;

    event NftConfigSet(address indexed _nft, INftHandler.NftConfig _nftConfig);
    event Staked(address indexed nft, uint256 tokenId, uint256 amount);

    function setUp() public {
        legionTest = new LegionStakingRulesTest();

        admin = address(111);
        vm.label(admin, "admin");
        harvesterFactory = address(222);
        vm.label(harvesterFactory, "harvesterFactory");
        extractorAddress = address(333);
        vm.label(extractorAddress, "extractorAddress");
        harvester = address(444);
        vm.label(harvester, "harvester");

        legionMetadataStore = address(new Mock("LegionMetadataStore"));

        maxLegionWeight = 2000e18;
        maxStakeableTotal = 100;
        boostFactor = 1e18;

        maxStakeable = 100;
        lifetime = 3600;

        nftErc721 = new ERC721Mintable();
        nftErc1155 = new ERC1155Mintable();

        erc721StakingRules = new LegionStakingRules(
            admin,
            harvesterFactory,
            ILegionMetadataStore(legionMetadataStore),
            maxLegionWeight,
            maxStakeableTotal,
            boostFactor
        );

        erc1155StakingRules = new ExtractorStakingRules(
            admin,
            harvesterFactory,
            address(nftErc1155),
            maxStakeable,
            lifetime
        );

        INftHandler.NftConfig memory erc721Config = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC721,
            stakingRules: IStakingRules(address(erc721StakingRules))
        });

        address[] memory nfts = new address[](1);
        nfts[0] = address(nftErc721);

        INftHandler.NftConfig[] memory nftConfigs = new INftHandler.NftConfig[](1);
        nftConfigs[0] = erc721Config;

        nftHandler = new NftHandler();
        nftHandler.init(admin, harvester, nfts, nftConfigs);

        vm.prank(harvesterFactory);
        erc721StakingRules.setNftHandler(address(nftHandler));
        vm.prank(harvesterFactory);
        erc1155StakingRules.setNftHandler(address(nftHandler));
    }

    function test_init() public {
        assertEq(nftHandler.getRoleAdmin(nftHandler.NH_ADMIN()), nftHandler.NH_ADMIN());
        assertTrue(nftHandler.hasRole(nftHandler.NH_ADMIN(), admin));
        assertEq(address(nftHandler.harvester()), harvester);
    }

    function test_getAllAllowedNFTs() public {
        address[] memory nfts = new address[](1);
        nfts[0] = address(nftErc721);

        assertAddressArrayEq(nftHandler.getAllAllowedNFTs(), nfts);
    }

    function test_getAllAllowedNFTsLength() public {
        assertEq(nftHandler.getAllAllowedNFTsLength(), 1);
    }

    function test_getSupportedInterface() public {
        assertEq(
            uint256(nftHandler.getSupportedInterface(address(1))),
            uint256(INftHandler.Interfaces.Unsupported)
        );

        assertEq(
            uint256(nftHandler.getSupportedInterface(address(nftErc721))),
            uint256(INftHandler.Interfaces.ERC721)
        );
    }

    function test_getStakingRules() public {
        assertEq(address(nftHandler.getStakingRules(address(1))), address(0));

        assertEq(
            address(nftHandler.getStakingRules(address(nftErc721))),
            address(IStakingRules(address(erc721StakingRules)))
        );
    }

    function test_getNftBoost() public {
        // use test cases from LegionStakingRulesTest
        for (uint256 i = 0; i < legionTest.testCasesLength(); i++) {
            LegionStakingRulesTest.TestCase memory testCase = legionTest.getTestCase(i);
            uint256 tokenId = i;

            ILegionMetadataStore.LegionMetadata memory metadata = legionTest.getMockMetadata(testCase.legionGeneration, testCase.legionRarity);

            vm.mockCall(
                legionMetadataStore,
                abi.encodeCall(ILegionMetadataStore.metadataForLegion, (tokenId)),
                abi.encode(metadata)
            );

            assertEq(nftHandler.getNftBoost(address(1), address(nftErc721), tokenId, 1), testCase.boost);
        }
    }

    struct HarvesterTotalBoostTestCase {
        uint256 stakingRulesBoost;
        uint256 totalBoost;
    }

    // workaround for "UnimplementedFeatureError: Copying of type struct memory to storage not yet supported."
    uint256 public constant harvesterTotalBoostTestCasesLength = 2;

    function getTotalBoostTestCase(uint256 _i) public pure returns (HarvesterTotalBoostTestCase memory) {
        HarvesterTotalBoostTestCase[harvesterTotalBoostTestCasesLength] memory testCases = [
            // TODO: add more test cases
            HarvesterTotalBoostTestCase(15e17, 15e17),
            HarvesterTotalBoostTestCase(15e17, 225e16)
        ];

        return testCases[_i];
    }

    function test_getHarvesterTotalBoost() public {
        INftHandler.NftConfig memory nullConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(address(0))
        });

        vm.prank(admin);
        nftHandler.setNftConfig(address(nftErc721), nullConfig);

        for (uint256 i = 0; i < harvesterTotalBoostTestCasesLength; i++) {
            HarvesterTotalBoostTestCase memory testCase = getTotalBoostTestCase(i);
            address nftAddress = address(uint160(i+999));

            INftHandler.NftConfig memory nftConfig = INftHandler.NftConfig({
                supportedInterface: INftHandler.Interfaces.ERC1155,
                stakingRules: IStakingRules(nftAddress)
            });

            vm.prank(admin);
            nftHandler.setNftConfig(nftAddress, nftConfig);

            vm.mockCall(
                nftAddress,
                abi.encodeCall(IStakingRules.getHarvesterBoost, ()),
                abi.encode(testCase.stakingRulesBoost)
            );

            assertEq(nftHandler.getHarvesterTotalBoost(), testCase.totalBoost);
        }
    }

    function test_setNftConfig() public {
        // check start state
        address[] memory arr = new address[](1);
        arr[0] = address(nftErc721);
        assertAddressArrayEq(nftHandler.getAllAllowedNFTs(), arr);

        assertEq(
            uint256(nftHandler.getSupportedInterface(address(nftErc721))),
            uint256(INftHandler.Interfaces.ERC721)
        );

        assertEq(
            address(nftHandler.getStakingRules(address(nftErc721))),
            address(erc721StakingRules)
        );

        assertEq(nftHandler.getAllAllowedNFTsLength(), 1);

        // zero out state

        INftHandler.NftConfig memory nullConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(address(0))
        });

        INftHandler.NftConfig memory emitConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.Unsupported,
            stakingRules: IStakingRules(address(0))
        });

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit NftConfigSet(address(nftErc721), emitConfig);
        nftHandler.setNftConfig(address(nftErc721), nullConfig);

        address[] memory emptyArr = new address[](0);
        assertAddressArrayEq(nftHandler.getAllAllowedNFTs(), emptyArr);

        assertEq(
            uint256(nftHandler.getSupportedInterface(address(nftErc721))),
            uint256(INftHandler.Interfaces.Unsupported)
        );

        assertEq(
            address(nftHandler.getStakingRules(address(nftErc721))),
            address(0)
        );

        assertEq(nftHandler.getAllAllowedNFTsLength(), 0);

        // set new state

        INftHandler.NftConfig memory newConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(address(111))
        });

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit NftConfigSet(address(nftErc1155), newConfig);
        nftHandler.setNftConfig(address(nftErc1155), newConfig);

        address[] memory newArr = new address[](1);
        newArr[0] = address(nftErc1155);
        assertAddressArrayEq(nftHandler.getAllAllowedNFTs(), newArr);

        assertEq(
            uint256(nftHandler.getSupportedInterface(address(nftErc1155))),
            uint256(INftHandler.Interfaces.ERC1155)
        );

        assertEq(
            address(nftHandler.getStakingRules(address(nftErc1155))),
            address(111)
        );

        assertEq(nftHandler.getAllAllowedNFTsLength(), 1);
    }

    function test_stakeNftERC721() public {
        vm.expectRevert("InvalidNftAddress()");
        nftHandler.stakeNft(address(0), 1, 1);

        vm.expectRevert("NothingToStake()");
        nftHandler.stakeNft(address(nftErc721), 1, 0);

        uint256 tokenId = 1;
        vm.mockCall(
            legionMetadataStore,
            abi.encodeCall(ILegionMetadataStore.metadataForLegion, (tokenId)),
            abi.encode(
                legionTest.getMockMetadata(
                    legionTest.getTestCase(0).legionGeneration,
                    legionTest.getTestCase(0).legionRarity
                )
            )
        );

        vm.expectRevert("WrongAmountForERC721()");
        nftHandler.stakeNft(address(nftErc721), tokenId, 10);

        vm.expectRevert("NftNotAllowed()");
        nftHandler.stakeNft(address(nftErc1155), tokenId, 10);

        nftErc721.mint(address(this), tokenId);
        nftErc721.approve(address(nftHandler), tokenId);

        address h = address(nftHandler.harvester());
        vm.mockCall(h, abi.encodeCall(IHarvester.updateNftBoost, (address(this))), abi.encode(true));

        vm.expectEmit(true, true, true, true);
        emit Staked(address(nftErc721), tokenId, 1);
        nftHandler.stakeNft(address(nftErc721), tokenId, 1);

        assertEq(nftHandler.stakedNfts(address(this), address(nftErc721), tokenId), 1);
        assertEq(
            nftHandler.getUserBoost(address(this)),
            nftHandler.getNftBoost(address(this), address(nftErc721), tokenId, 1)
        );
        assertEq(nftErc721.ownerOf(tokenId), address(nftHandler));

        vm.expectRevert("NftAlreadyStaked()");
        nftHandler.stakeNft(address(nftErc721), tokenId, 1);
    }

    function test_stakeNftERC1155() public {
        uint256 tokenId = 1;
        uint256 amount = 20;

        INftHandler.NftConfig memory newConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(erc1155StakingRules)
        });

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit NftConfigSet(address(nftErc1155), newConfig);
        nftHandler.setNftConfig(address(nftErc1155), newConfig);

        address h = address(nftHandler.harvester());
        vm.mockCall(h, abi.encodeCall(IHarvester.updateNftBoost, (address(this))), abi.encode(true));

        nftErc1155.mint(address(this), tokenId, amount);
        nftErc1155.setApprovalForAll(address(nftHandler), true);

        vm.expectEmit(true, true, true, true);
        emit Staked(address(nftErc1155), tokenId, amount);
        nftHandler.stakeNft(address(nftErc1155), tokenId, amount);

        assertEq(nftHandler.stakedNfts(address(this), address(nftErc1155), tokenId), amount);
        assertEq(
            nftHandler.getUserBoost(address(this)),
            nftHandler.getNftBoost(address(this), address(nftErc1155), tokenId, amount)
        );
        assertEq(nftErc1155.balanceOf(address(nftHandler), tokenId), amount);

        uint256 newAmount = 7;
        uint256 currentUserBoost = nftHandler.getUserBoost(address(this));

        nftErc1155.mint(address(this), tokenId, newAmount);

        vm.expectEmit(true, true, true, true);
        emit Staked(address(nftErc1155), tokenId, newAmount);
        nftHandler.stakeNft(address(nftErc1155), tokenId, newAmount);

        assertEq(nftHandler.stakedNfts(address(this), address(nftErc1155), tokenId), amount + newAmount);
        assertEq(
            nftHandler.getUserBoost(address(this)),
            currentUserBoost + nftHandler.getNftBoost(address(this), address(nftErc1155), tokenId, newAmount)
        );
        assertEq(nftErc1155.balanceOf(address(nftHandler), tokenId), amount + newAmount);
    }

    function stakeNftHelperERC721(uint256 tokenId) public {
        vm.mockCall(
            legionMetadataStore,
            abi.encodeCall(ILegionMetadataStore.metadataForLegion, (tokenId)),
            abi.encode(
                legionTest.getMockMetadata(
                    legionTest.getTestCase(0).legionGeneration,
                    legionTest.getTestCase(0).legionRarity
                )
            )
        );

        address h = address(nftHandler.harvester());
        vm.mockCall(h, abi.encodeCall(IHarvester.updateNftBoost, (address(this))), abi.encode(true));

        nftErc721.mint(address(this), tokenId);
        nftErc721.approve(address(nftHandler), tokenId);
        nftHandler.stakeNft(address(nftErc721), tokenId, 1);
    }

    function stakeNftHelperERC1155(uint256 tokenId, uint256 amount) public {
        INftHandler.NftConfig memory newConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(erc1155StakingRules)
        });

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit NftConfigSet(address(nftErc1155), newConfig);
        nftHandler.setNftConfig(address(nftErc1155), newConfig);

        address h = address(nftHandler.harvester());
        vm.mockCall(h, abi.encodeCall(IHarvester.updateNftBoost, (address(this))), abi.encode(true));

        nftErc1155.mint(address(this), tokenId, amount);
        nftErc1155.setApprovalForAll(address(nftHandler), true);
        nftHandler.stakeNft(address(nftErc1155), tokenId, amount);
    }

    function test_unstakeNft() public {
        uint256 tokenId = 1;
        uint256 amount = 20;

        stakeNftHelperERC721(tokenId);
        stakeNftHelperERC1155(tokenId, amount);

        vm.expectRevert("InvalidNftAddress()");
        nftHandler.unstakeNft(address(0), tokenId, 1);

        vm.expectRevert("NothingToStake()");
        nftHandler.unstakeNft(address(nftErc721), tokenId, 0);

        vm.expectRevert("WrongAmountForERC721()");
        nftHandler.unstakeNft(address(nftErc721), tokenId, 10);

        uint256 wrongTokenId = 10;
        vm.mockCall(
            legionMetadataStore,
            abi.encodeCall(ILegionMetadataStore.metadataForLegion, (wrongTokenId)),
            abi.encode(
                legionTest.getMockMetadata(
                    legionTest.getTestCase(0).legionGeneration,
                    legionTest.getTestCase(0).legionRarity
                )
            )
        );

        vm.expectRevert("NftNotStaked()");
        nftHandler.unstakeNft(address(nftErc721), wrongTokenId, 1);

        vm.expectRevert("NftNotAllowed()");
        nftHandler.unstakeNft(address(1), tokenId, 1);

        vm.mockCall(
            address(erc1155StakingRules),
            abi.encodeCall(IStakingRules.canUnstake, (address(this), address(nftErc1155), tokenId, amount + 1)),
            abi.encode(bytes(""))
        );
        nftErc1155.mint(address(nftHandler), tokenId, 1);

        vm.expectRevert("AmountTooBig()");
        nftHandler.unstakeNft(address(nftErc1155), tokenId, amount + 1);

        uint256 currentUserBoost = nftHandler.getUserBoost(address(this));

        nftHandler.unstakeNft(address(nftErc721), tokenId, 1);

        assertEq(nftHandler.stakedNfts(address(this), address(nftErc721), tokenId), 0);
        assertEq(
            nftHandler.getUserBoost(address(this)),
            currentUserBoost - nftHandler.getNftBoost(address(this), address(nftErc721), tokenId, 1)
        );
        assertEq(nftErc721.ownerOf(tokenId), address(this));
    }

    function test_replaceExtractor() public {
        uint256 tokenId = 1;
        uint256 amount = 20;
        uint256 replacedSpotId = 0;

        vm.expectRevert("InvalidNftAddress()");
        nftHandler.replaceExtractor(address(0), tokenId, amount, replacedSpotId);

        vm.expectRevert("NothingToStake()");
        nftHandler.replaceExtractor(address(nftErc1155), tokenId, 0, replacedSpotId);

        vm.expectRevert("StakingRulesRequired()");
        nftHandler.replaceExtractor(address(nftErc1155), tokenId, amount, replacedSpotId);

        vm.expectRevert("MustBeERC1155()");
        nftHandler.replaceExtractor(address(nftErc721), tokenId, amount, replacedSpotId);

        stakeNftHelperERC1155(tokenId, amount);

        uint256 replaceTokenId = 3;
        uint256 replaceAmount = 1;
        (, IStakingRules stakingRules) = nftHandler.allowedNfts(address(nftErc1155));
        vm.prank(admin);
        ExtractorStakingRules(address(stakingRules)).setExtractorBoost(replaceTokenId, 1);

        nftErc1155.mint(address(this), replaceTokenId, replaceAmount);
        nftErc1155.setApprovalForAll(address(nftHandler), true);

        nftHandler.replaceExtractor(address(nftErc1155), replaceTokenId, replaceAmount, replacedSpotId);

        assertEq(nftHandler.stakedNfts(address(this), address(nftErc1155), tokenId), amount - 1);
        assertEq(nftHandler.stakedNfts(address(this), address(nftErc1155), replaceTokenId), 1);
        assertEq(nftErc1155.balanceOf(address(nftHandler), tokenId), amount - 1);
        assertEq(nftErc1155.balanceOf(address(nftHandler), replaceTokenId), 1);
    }
}

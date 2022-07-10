pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/ERC721Mintable.sol";
import "foundry/lib/ERC1155Mintable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "contracts/harvester/HarvesterFactory.sol";
import "contracts/harvester/Harvester.sol";
import "contracts/harvester/NftHandler.sol";
import "contracts/harvester/rules/LegionStakingRules.sol";
import "contracts/harvester/rules/TreasureStakingRules.sol";
import "contracts/harvester/rules/ExtractorStakingRules.sol";

contract HarvesterFactoryTest is TestUtils {
    HarvesterFactory public harvesterFactory;

    address public admin = address(111);
    address public parts = address(222);

    address public harvesterImpl;
    address public nftHandlerImpl;

    IERC20 public magic = IERC20(address(333));
    IMiddleman public middleman = IMiddleman(address(444));

    address public legionMetadataStore = address(555);
    uint256 public maxLegionWeight = 2000e18;
    uint256 public maxStakeableTotal = 100;
    uint256 public boostFactor = 1e18;

    uint256 public maxStakeableTreasuresPerUser = 20;
    uint256 public maxStakeable = 100;
    uint256 public lifetime = 3600;

    ERC721Mintable public nftErc721;
    ERC1155Mintable public nftErc1155;
    ERC1155Mintable public nftErc1155Treasures;

    LegionStakingRules public erc721StakingRules;
    ExtractorStakingRules public erc1155StakingRules;
    TreasureStakingRules public erc1155TreasureStakingRules;

    uint256 public initTotalDepositCap = 10_000_000e18;

    IHarvester.CapConfig public initDepositCapPerWallet = IHarvester.CapConfig({
        parts: parts,
        capPerPart: 1e18
    });

    event Magic(IERC20 magic);
    event Middleman(IMiddleman middleman);
    event Upgraded(address indexed implementation);

    function setUp() public {
        vm.label(admin, "admin");
        address impl;

        harvesterImpl = address(new Harvester());
        nftHandlerImpl = address(new NftHandler());

        address[] memory emptyArray = new address[](0);
        INftHandler.NftConfig[] memory emptyConfig = new INftHandler.NftConfig[](0);

        impl = address(new HarvesterFactory());

        harvesterFactory = HarvesterFactory(address(new ERC1967Proxy(impl, bytes(""))));
        harvesterFactory.init(
            magic,
            middleman,
            admin,
            harvesterImpl,
            nftHandlerImpl
        );

        nftErc721 = new ERC721Mintable();
        nftErc1155 = new ERC1155Mintable();
        nftErc1155Treasures = new ERC1155Mintable();

        impl = address(new LegionStakingRules());

        erc721StakingRules = LegionStakingRules(address(new ERC1967Proxy(impl, bytes(""))));
        erc721StakingRules.init(
            admin,
            address(harvesterFactory),
            ILegionMetadataStore(legionMetadataStore),
            maxLegionWeight,
            maxStakeableTotal,
            boostFactor
        );

        impl = address(new TreasureStakingRules());

        erc1155TreasureStakingRules = TreasureStakingRules(address(new ERC1967Proxy(impl, bytes(""))));
        erc1155TreasureStakingRules.init(
            admin,
            address(harvesterFactory),
            maxStakeableTreasuresPerUser
        );

        impl = address(new ExtractorStakingRules());

        erc1155StakingRules = ExtractorStakingRules(address(new ERC1967Proxy(impl, bytes(""))));
        erc1155StakingRules.init(
            admin,
            address(harvesterFactory),
            address(nftErc1155),
            maxStakeable,
            lifetime
        );
    }

    function test_constructor() public {
        assertEq(harvesterFactory.getRoleAdmin(harvesterFactory.HF_ADMIN()), harvesterFactory.HF_ADMIN());
        assertTrue(harvesterFactory.hasRole(harvesterFactory.HF_ADMIN(), admin));

        assertEq(harvesterFactory.getRoleAdmin(harvesterFactory.HF_DEPLOYER()), harvesterFactory.HF_ADMIN());
        assertTrue(harvesterFactory.hasRole(harvesterFactory.HF_DEPLOYER(), admin));

        assertEq(harvesterFactory.getRoleAdmin(harvesterFactory.HF_BEACON_ADMIN()), harvesterFactory.HF_ADMIN());
        assertTrue(harvesterFactory.hasRole(harvesterFactory.HF_BEACON_ADMIN(), admin));

        assertTrue(address(harvesterFactory.harvesterBeacon()) != address(0));
        assertTrue(address(harvesterFactory.nftHandlerBeacon()) != address(0));
    }

    function getNftAndNftConfig() public view returns (address[] memory, INftHandler.NftConfig[] memory) {
        INftHandler.NftConfig memory erc721Config = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC721,
            stakingRules: IStakingRules(address(erc721StakingRules))
        });

        INftHandler.NftConfig memory erc1155TreasuresConfig = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(address(erc1155TreasureStakingRules))
        });

        INftHandler.NftConfig memory erc1155Config = INftHandler.NftConfig({
            supportedInterface: INftHandler.Interfaces.ERC1155,
            stakingRules: IStakingRules(address(erc1155StakingRules))
        });

        address[] memory nfts = new address[](3);
        nfts[0] = address(nftErc721);
        nfts[1] = address(nftErc1155);
        nfts[2] = address(nftErc1155Treasures);

        INftHandler.NftConfig[] memory nftConfigs = new INftHandler.NftConfig[](3);
        nftConfigs[0] = erc721Config;
        nftConfigs[1] = erc1155Config;
        nftConfigs[2] = erc1155TreasuresConfig;

        return (nfts, nftConfigs);
    }

    function checkHarvesterInit(IHarvester _harvester, INftHandler _nftHandler) public {
        Harvester harvester = Harvester(address(_harvester));
        assertTrue(harvester.hasRole(harvester.HARVESTER_ADMIN(), admin));
        assertEq(harvester.getRoleAdmin(harvester.HARVESTER_ADMIN()), harvester.HARVESTER_ADMIN());
        assertEq(harvester.totalDepositCap(), initTotalDepositCap);
        assertEq(address(harvester.factory()), address(harvesterFactory));
        assertEq(address(harvester.nftHandler()), address(_nftHandler));

        (address initParts, uint256 initCapPerPart) = harvester.depositCapPerWallet();
        assertEq(initParts, initDepositCapPerWallet.parts);
        assertEq(initCapPerPart, initDepositCapPerWallet.capPerPart);
    }

    function checkNftHandlerInit(INftHandler _nftHandler, IHarvester _harvester) public {
        NftHandler nftHandler = NftHandler(address(_nftHandler));
        assertEq(nftHandler.getRoleAdmin(nftHandler.NH_ADMIN()), nftHandler.NH_ADMIN());
        assertTrue(nftHandler.hasRole(nftHandler.NH_ADMIN(), admin));
        assertEq(address(nftHandler.harvester()), address(_harvester));
    }

    function test_deployHarvester() public {
        assertEq(harvesterFactory.getHarvester(0), address(0));
        address[] memory emptyArray = new address[](0);
        assertAddressArrayEq(harvesterFactory.getAllHarvesters(), emptyArray);
        assertEq(harvesterFactory.getAllHarvestersLength(), 0);

        (address[] memory nfts, INftHandler.NftConfig[] memory nftConfigs) = getNftAndNftConfig();

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_DEPLOYER());
        vm.expectRevert(errorMsg);
        harvesterFactory.deployHarvester(admin, initDepositCapPerWallet, nfts, nftConfigs);

        vm.prank(admin);
        harvesterFactory.deployHarvester(admin, initDepositCapPerWallet, nfts, nftConfigs);

        IHarvester harvester = IHarvester(harvesterFactory.getHarvester(0));

        vm.expectRevert("Initializable: contract is already initialized");
        harvester.init(
            address(2),
            INftHandler(address(2)),
            IHarvester.CapConfig({
                parts: address(2),
                capPerPart: 2
            })
        );

        address[] memory harvesters = new address[](1);
        harvesters[0] = address(harvester);

        assertAddressArrayEq(harvesterFactory.getAllHarvesters(), harvesters);
        assertEq(harvesterFactory.getAllHarvestersLength(), 1);

        INftHandler.NftConfig[] memory emptyConfig = new INftHandler.NftConfig[](0);
        INftHandler nftHandler = harvester.nftHandler();

        vm.expectRevert("Initializable: contract is already initialized");
        nftHandler.init(address(2), address(2), emptyArray, emptyConfig);

        checkHarvesterInit(harvester, nftHandler);
        checkNftHandlerInit(nftHandler, harvester);
    }

    function deployHarvester() public returns (IHarvester) {
        (address[] memory nfts, INftHandler.NftConfig[] memory nftConfigs) = getNftAndNftConfig();

        vm.prank(admin);
        harvesterFactory.deployHarvester(admin, initDepositCapPerWallet, nfts, nftConfigs);

        return IHarvester(harvesterFactory.getHarvester(0));
    }

    function test_enableHarvester() public {
        IHarvester harvester = deployHarvester();

        assertEq(harvester.disabled(), false);

        vm.prank(address(harvesterFactory));
        harvester.disable();

        assertEq(harvester.disabled(), true);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_DEPLOYER());
        vm.expectRevert(errorMsg);
        harvesterFactory.enableHarvester(harvester);

        vm.prank(admin);
        harvesterFactory.enableHarvester(harvester);

        assertEq(harvester.disabled(), false);
    }

    function test_disableHarvester() public {
        IHarvester harvester = deployHarvester();

        assertEq(harvester.disabled(), false);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_DEPLOYER());
        vm.expectRevert(errorMsg);
        harvesterFactory.disableHarvester(harvester);

        vm.prank(admin);
        harvesterFactory.disableHarvester(harvester);

        assertEq(harvester.disabled(), true);
    }

    function test_setMagicToken() public {
        assertEq(address(harvesterFactory.magic()), address(magic));

        IERC20 newMagic = IERC20(address(76));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_ADMIN());
        vm.expectRevert(errorMsg);
        harvesterFactory.setMagicToken(newMagic);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit Magic(newMagic);
        harvesterFactory.setMagicToken(newMagic);

        assertEq(address(harvesterFactory.magic()), address(newMagic));
    }

    function test_setMiddleman() public {
        assertEq(address(harvesterFactory.middleman()), address(middleman));

        IMiddleman newMiddleman = IMiddleman(address(77));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_ADMIN());
        vm.expectRevert(errorMsg);
        harvesterFactory.setMiddleman(newMiddleman);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit Middleman(newMiddleman);
        harvesterFactory.setMiddleman(newMiddleman);

        assertEq(address(harvesterFactory.middleman()), address(newMiddleman));
    }

    function test_upgradeHarvesterTo() public {
        assertEq(harvesterFactory.harvesterBeacon().implementation(), harvesterImpl);

        address newHarvesterImpl = address(78);
        vm.etch(newHarvesterImpl, bytes("0x42"));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_BEACON_ADMIN());
        vm.expectRevert(errorMsg);
        harvesterFactory.upgradeHarvesterTo(newHarvesterImpl);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit Upgraded(newHarvesterImpl);
        harvesterFactory.upgradeHarvesterTo(newHarvesterImpl);

        assertEq(harvesterFactory.harvesterBeacon().implementation(), newHarvesterImpl);
    }

    function test_upgradeNftHandlerTo() public {
        assertEq(harvesterFactory.nftHandlerBeacon().implementation(), nftHandlerImpl);

        address newNftHandlerImpl = address(79);
        vm.etch(newNftHandlerImpl, bytes("0x42"));

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), harvesterFactory.HF_BEACON_ADMIN());
        vm.expectRevert(errorMsg);
        harvesterFactory.upgradeNftHandlerTo(newNftHandlerImpl);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit Upgraded(newNftHandlerImpl);
        harvesterFactory.upgradeNftHandlerTo(newNftHandlerImpl);

        assertEq(harvesterFactory.nftHandlerBeacon().implementation(), newNftHandlerImpl);
    }
}

pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/Mock.sol";

import "contracts/harvester/interfaces/INftHandler.sol";
import "contracts/harvester/interfaces/IHarvester.sol";
import "contracts/harvester/rules/PartsStakingRules.sol";


contract PartsStakingRulesTest is TestUtils {
    PartsStakingRules public partsRules;

    address public admin;
    address public harvester;
    address public harvesterFactory;
    address public nftHandler;
    uint256 public maxStakeableTotal;
    uint256 public maxStakeablePerUser;
    uint256 public boostFactor;

    event MaxStakeableTotal(uint256 maxStakeableTotal);
    event MaxStakeablePerUser(uint256 maxStakeablePerUser);
    event BoostFactor(uint256 boostFactor);

    function setUp() public {
        admin = address(111);
        harvesterFactory = address(222);

        harvester = address(new Mock("Harvester"));
        nftHandler = address(new Mock("NftHandler"));

        maxStakeableTotal = 800;
        maxStakeablePerUser = 40;
        boostFactor = 1e18;

        partsRules = new PartsStakingRules(admin, harvesterFactory, maxStakeableTotal, maxStakeablePerUser, boostFactor);
    }

    function test_getUserBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) public {
        assertEq(partsRules.getUserBoost(_user, _nft, _tokenId, _amount), 0);
    }

    function test_getHarvesterBoost() public {
        address user = address(11);
        address nft = address(12);
        uint256 tokenId = 9;

        vm.mockCall(
            nftHandler,
            abi.encodeCall(INftHandler.harvester, ()),
            abi.encode(harvester)
        );

        vm.mockCall(
            harvester,
            abi.encodeCall(IHarvester.isMaxUserGlobalDeposit, (user)),
            abi.encode(false)
        );

        vm.prank(harvesterFactory);
        partsRules.setNftHandler(nftHandler);

        uint256[4][8] memory testData = [
            // TODO: add more test cases
            // staked, maxStakeableTotal, boostFactor, harvesterBoost
            [uint256(1), 10, 1e18, 119e16],
            [uint256(2), 10, 1e18, 136e16],

            // vary maxStakeableTotal and staked
            [uint256(1), 800, 1e18, 10024984375e8],
            // harvesterBoost = 1.0024984375
            [uint256(2), 800, 1e18, 100499375e10],
            // harvesterBoost = 1.00499375
            [uint256(20), 800, 1e18, 1049375e12],
            // harvesterBoost = 1.049375
            [uint256(40), 800, 1e18, 10975e14],
            // harvesterBoost = 1.0975

            // vary boostFactor
            [uint256(40), 800, 2e18, 1195e15],
            // harvesterBoost = 1.195

            // vary maxStakeableTotal
            [uint256(40), 1200, 1e18, 1065555555555555555]
            // harvesterBoost = 1.065555555555555555
        ];

        for (uint256 i = 0; i < testData.length; i++) {
            uint256 amount = testData[i][0];
            uint256 maxStakeable = testData[i][1];
            uint256 boost = testData[i][2];
            uint256 harvesterBoost = testData[i][3];

            vm.prank(nftHandler);
            partsRules.canStake(user, nft, tokenId, amount);
            vm.prank(admin);
            partsRules.setMaxStakeableTotal(maxStakeable);
            vm.prank(admin);
            partsRules.setBoostFactor(boost);

            assertEq(partsRules.getHarvesterBoost(), harvesterBoost);

            // reset staked to 0
            vm.prank(nftHandler);
            partsRules.canUnstake(user, nft, tokenId, amount);
        }
    }

    function test_canStake(
        address _user,
        address _nft,
        uint256 _tokenId,
        uint256 _amount,
        address _user2,
        address _nft2,
        uint256 _tokenId2
    ) public {
        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), partsRules.SR_NFT_HANDLER());
        vm.expectRevert(errorMsg);
        partsRules.canStake(_user, _nft, _tokenId, _amount);

        vm.prank(harvesterFactory);
        partsRules.setNftHandler(address(this));

        vm.expectRevert("ZeroAddress()");
        partsRules.canStake(address(0), _nft, _tokenId, _amount);

        vm.assume(_user != address(0));

        vm.expectRevert("ZeroAmount()");
        partsRules.canStake(_user, _nft, _tokenId, 0);

        vm.assume(maxStakeableTotal < _amount && _amount < type(uint256).max / 10);

        vm.expectRevert("MaxStakeable()");
        partsRules.canStake(_user, _nft, _tokenId, _amount);

        vm.prank(admin);
        partsRules.setMaxStakeableTotal(_amount * 10);

        vm.expectRevert("MaxStakeablePerUser()");
        partsRules.canStake(_user, _nft, _tokenId, _amount);

        vm.prank(admin);
        partsRules.setMaxStakeablePerUser(_amount * 2);

        partsRules.canStake(_user, _nft, _tokenId, _amount);

        assertEq(partsRules.staked(), _amount);
        assertEq(partsRules.getAmountStaked(_user), _amount);

        partsRules.canStake(_user, _nft, _tokenId, _amount);

        assertEq(partsRules.staked(), _amount * 2);
        assertEq(partsRules.getAmountStaked(_user), _amount * 2);

        vm.expectRevert("MaxStakeablePerUser()");
        partsRules.canStake(_user, _nft, _tokenId, _amount);

        assertEq(partsRules.staked(), _amount * 2);
        assertEq(partsRules.getAmountStaked(_user), _amount * 2);

        vm.assume(_user2 != address(0) && _user != _user2);

        partsRules.canStake(_user2, _nft2, _tokenId2, _amount);

        assertEq(partsRules.staked(), _amount * 3);
        assertEq(partsRules.getAmountStaked(_user2), _amount);

        vm.expectRevert("MaxStakeablePerUser()");
        partsRules.canStake(_user2, _nft2, _tokenId2, _amount + 1);
    }

    function test_canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount) public {
        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), partsRules.SR_NFT_HANDLER());
        vm.expectRevert(errorMsg);
        partsRules.canUnstake(_user, _nft, _tokenId, _amount);

        vm.prank(harvesterFactory);
        partsRules.setNftHandler(nftHandler);

        vm.prank(nftHandler);
        vm.expectRevert("ZeroAddress()");
        partsRules.canUnstake(address(0), _nft, _tokenId, _amount);

        vm.assume(_user != address(0));

        vm.prank(nftHandler);
        vm.expectRevert("ZeroAmount()");
        partsRules.canUnstake(_user, _nft, _tokenId, 0);

        vm.assume(maxStakeableTotal < _amount && _amount < type(uint256).max / 2);

        vm.prank(admin);
        partsRules.setMaxStakeableTotal(_amount * 2);

        vm.prank(admin);
        partsRules.setMaxStakeablePerUser(_amount);

        vm.prank(nftHandler);
        partsRules.canStake(_user, _nft, _tokenId, _amount);

        vm.mockCall(
            nftHandler,
            abi.encodeCall(INftHandler.harvester, ()),
            abi.encode(harvester)
        );

        vm.mockCall(
            harvester,
            abi.encodeCall(IHarvester.isMaxUserGlobalDeposit, (_user)),
            abi.encode(true)
        );

        vm.prank(nftHandler);
        vm.expectRevert("MinUserGlobalDeposit()");
        partsRules.canUnstake(_user, _nft, _tokenId, _amount);

        assertEq(partsRules.staked(), _amount);
        assertEq(partsRules.getAmountStaked(_user), _amount);

        vm.mockCall(
            harvester,
            abi.encodeCall(IHarvester.isMaxUserGlobalDeposit, (_user)),
            abi.encode(false)
        );

        vm.prank(nftHandler);
        partsRules.canUnstake(_user, _nft, _tokenId, _amount - 1);

        assertEq(partsRules.staked(), 1);
        assertEq(partsRules.getAmountStaked(_user), 1);

        vm.prank(nftHandler);
        partsRules.canUnstake(_user, _nft, _tokenId, 1);

        assertEq(partsRules.staked(), 0);
        assertEq(partsRules.getAmountStaked(_user), 0);
    }

    function test_setNftHandler(address _nftHandler) public {
        assertEq(partsRules.hasRole(partsRules.SR_NFT_HANDLER(), _nftHandler), false);
        assertEq(partsRules.hasRole(partsRules.SR_HARVESTER_FACTORY(), harvesterFactory), true);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), partsRules.SR_HARVESTER_FACTORY());
        vm.expectRevert(errorMsg);
        partsRules.setNftHandler(_nftHandler);

        vm.prank(harvesterFactory);
        partsRules.setNftHandler(_nftHandler);

        assertEq(partsRules.hasRole(partsRules.SR_NFT_HANDLER(), _nftHandler), true);
        assertEq(partsRules.hasRole(partsRules.SR_HARVESTER_FACTORY(), harvesterFactory), false);
    }

    function test_setMaxStakeableTotal(uint256 _maxStakeableTotal) public {
        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), partsRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        partsRules.setMaxStakeableTotal(_maxStakeableTotal);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MaxStakeableTotal(_maxStakeableTotal);

        partsRules.setMaxStakeableTotal(_maxStakeableTotal);
        assertEq(partsRules.maxStakeableTotal(), _maxStakeableTotal);
    }

    function test_setMaxStakeablePerUser(uint256 _maxStakeablePerUser) public {
        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), partsRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        partsRules.setMaxStakeablePerUser(_maxStakeablePerUser);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MaxStakeablePerUser(_maxStakeablePerUser);
        partsRules.setMaxStakeablePerUser(_maxStakeablePerUser);
        assertEq(partsRules.maxStakeablePerUser(), _maxStakeablePerUser);
    }

    function test_setBoostFactor(uint256 _boostFactor) public {
        vm.assume(_boostFactor > 1e17);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), partsRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        partsRules.setBoostFactor(_boostFactor);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit BoostFactor(_boostFactor);
        partsRules.setBoostFactor(_boostFactor);
        assertEq(partsRules.boostFactor(), _boostFactor);
    }
}

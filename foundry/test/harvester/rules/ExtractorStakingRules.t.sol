pragma solidity ^0.8.0;

import "foundry/lib/TestUtils.sol";
import "foundry/lib/Mock.sol";

import "contracts/harvester/interfaces/INftHandler.sol";
import "contracts/harvester/interfaces/IHarvester.sol";
import 'contracts/harvester/lib/Constant.sol';
import "contracts/harvester/rules/ExtractorStakingRules.sol";

contract ExtractorStakingRulesTest is TestUtils {
    ExtractorStakingRules public extractorRules;

    address public admin;
    address public harvesterFactory;
    address public extractorAddress;
    uint256 public maxStakeable;
    uint256 public lifetime;

    event MaxStakeable(uint256 maxStakeable);
    event ExtractorBoost(uint256 tokenId, uint256 boost);
    event ExtractorStaked(uint256 tokenId, uint256 amount);
    event ExtractorReplaced(uint256 tokenId, uint256 replacedSpotId);
    event Lifetime(uint256 lifetime);
    event ExtractorAddress(address extractorAddress);

    function setUp() public {
        admin = address(111);
        vm.label(admin, "admin");
        harvesterFactory = address(222);
        vm.label(harvesterFactory, "harvesterFactory");
        extractorAddress = address(333);
        vm.label(extractorAddress, "extractorAddress");

        maxStakeable = 10;
        lifetime = 3600;

        extractorRules = new ExtractorStakingRules(admin, harvesterFactory, extractorAddress, maxStakeable, lifetime);
    }

    function stakeExtractor(address _user, uint256 _tokenId, uint256 _amount) public {
        if (!extractorRules.hasRole(extractorRules.SR_NFT_HANDLER(), address(this))) {
            vm.prank(harvesterFactory);
            extractorRules.setNftHandler(address(this));
        }

        extractorRules.canStake(_user, extractorAddress, _tokenId, _amount);
    }

    function test_canStake(
        address _user,
        uint256 _tokenId,
        uint256 _amount
    ) public {
        vm.assume(0 < _amount && _amount < maxStakeable);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_NFT_HANDLER());
        vm.expectRevert(errorMsg);
        extractorRules.canStake(_user, extractorAddress, _tokenId, _amount);

        vm.prank(harvesterFactory);
        extractorRules.setNftHandler(address(this));

        vm.expectRevert("InvalidAddress()");
        extractorRules.canStake(_user, address(999), _tokenId, _amount);

        vm.expectRevert("ZeroAmount()");
        extractorRules.canStake(_user, extractorAddress, _tokenId, 0);

        vm.expectRevert(bytes("MaxStakeable()"));
        extractorRules.canStake(_user, extractorAddress, _tokenId, maxStakeable + 1);

        assertEq(extractorRules.getExtractorCount(), 0);

        vm.expectEmit(true, true, true, true);
        emit ExtractorStaked(_tokenId, _amount);
        extractorRules.canStake(_user, extractorAddress, _tokenId, _amount);

        assertEq(extractorRules.getExtractorCount(), _amount);

        ExtractorStakingRules.ExtractorData[] memory extractors = extractorRules.getExtractors();

        for (uint256 i = 0; i < _amount; i++) {
            (address user, uint256 tokenId, uint256 stakedTimestamp) = extractorRules.stakedExtractor(i);
            assertEq(user, address(this));
            assertEq(tokenId, _tokenId);
            assertEq(extractors[i].tokenId, _tokenId);
            assertEq(stakedTimestamp, block.timestamp);
            assertEq(extractors[i].stakedTimestamp, block.timestamp);
        }

        assertEq(extractorRules.getExtractorsTotalBoost(), 0);
        assertEq(extractorRules.getHarvesterBoost(), 1e18);
        vm.prank(admin);
        extractorRules.setExtractorBoost(_tokenId, 1e18);
        assertEq(extractorRules.getExtractorsTotalBoost(), _amount * 1e18);
        assertEq(extractorRules.getHarvesterBoost(), _amount * 1e18 + 1e18);

        assertEq(extractorRules.getUserBoost(_user, extractorAddress, _tokenId, _amount), 0);
    }

    function test_canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount) public {
        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_NFT_HANDLER());
        vm.expectRevert(errorMsg);
        extractorRules.canUnstake(_user, _nft, _tokenId, _amount);

        vm.prank(harvesterFactory);
        extractorRules.setNftHandler(address(this));

        vm.expectRevert("CannotUnstake()");
        extractorRules.canUnstake(_user, _nft, _tokenId, _amount);
    }

    function test_canReplace(address _user, uint256 _tokenId, uint256 _amount) public {
        vm.assume(0 < _amount && _amount < maxStakeable);
        vm.assume(_tokenId < type(uint256).max);

        uint256 boost1 = 5e17;
        uint256 boost2 = 6e17;
        uint256 newTokenId = _tokenId + 1;
        uint256 spotId = 0;
        uint256 timestamp = block.timestamp;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_NFT_HANDLER());
        vm.expectRevert(errorMsg);
        extractorRules.canReplace(_user, extractorAddress, _tokenId, _amount, spotId);

        stakeExtractor(_user, _tokenId, _amount);
        vm.prank(admin);
        extractorRules.setExtractorBoost(_tokenId, boost1);
        vm.prank(admin);
        extractorRules.setExtractorBoost(newTokenId, boost2);

        vm.expectRevert("InvalidAddress()");
        extractorRules.canReplace(_user, address(999), _tokenId, 1, spotId);

        vm.expectRevert("ZeroAmount()");
        extractorRules.canReplace(_user, extractorAddress, _tokenId, 0, spotId);

        vm.expectRevert("MustReplaceOne()");
        extractorRules.canReplace(_user, extractorAddress, newTokenId, 2, spotId);

        vm.expectRevert("InvalidSpotId()");
        extractorRules.canReplace(_user, extractorAddress, newTokenId, 1, maxStakeable);

        vm.expectRevert("MustReplaceWithHigherBoost()");
        extractorRules.canReplace(_user, extractorAddress, _tokenId, 1, spotId);

        (address user, uint256 stakedTokenId, uint256 stakedTimestamp) = extractorRules.stakedExtractor(spotId);
        assertEq(user, address(this));
        assertEq(stakedTokenId, _tokenId);
        assertEq(stakedTimestamp, timestamp);

        vm.warp(timestamp + 10);

        vm.expectEmit(true, true, true, true);
        emit ExtractorReplaced(newTokenId, spotId);
        extractorRules.canReplace(_user, extractorAddress, newTokenId, 1, spotId);

        (address user2, uint256 stakedTokenId2, uint256 stakedTimestamp2) = extractorRules.stakedExtractor(spotId);
        assertEq(user2, address(this));
        assertEq(stakedTokenId2, newTokenId);
        assertEq(stakedTimestamp2, timestamp + 10);
    }

    function test_isExtractorActive(address _user, uint256 _tokenId, uint256 _amount) public {
        vm.assume(0 < _amount && _amount < maxStakeable);
        assertEq(extractorRules.getExtractorCount(), 0);

        stakeExtractor(_user, _tokenId, _amount);

        for (uint256 i = 0; i < _amount; i++) {
            assertEq(extractorRules.isExtractorActive(i), true);
        }

        vm.warp(block.timestamp + lifetime);

        for (uint256 i = 0; i < _amount; i++) {
            assertEq(extractorRules.isExtractorActive(i), true);
        }

        vm.warp(block.timestamp + 1);

        for (uint256 i = 0; i < _amount; i++) {
            assertEq(extractorRules.isExtractorActive(i), false);
        }
    }

    function test_getExtractorCount(uint256 _amount) public {
        vm.assume(0 < _amount && _amount < maxStakeable);

        address user = address(999);
        uint256 tokenId = 9;

        assertEq(extractorRules.getExtractorCount(), 0);
        stakeExtractor(user, tokenId, _amount);
        assertEq(extractorRules.getExtractorCount(), _amount);

        stakeExtractor(user, tokenId, maxStakeable - _amount);
        assertEq(extractorRules.getExtractorCount(), maxStakeable);

        vm.expectRevert(bytes("MaxStakeable()"));
        extractorRules.canStake(user, extractorAddress, tokenId, 1);

        assertEq(extractorRules.getExtractorCount(), maxStakeable);
    }

    function test_getExtractors(uint256 _amount) public {
        vm.assume(0 < _amount && _amount < maxStakeable);

        address user = address(999);
        uint256 tokenId = 9;

        stakeExtractor(user, tokenId, _amount);

        ExtractorStakingRules.ExtractorData[] memory extractors = extractorRules.getExtractors();

        for (uint256 i = 0; i < _amount; i++) {
            assertEq(extractors[i].tokenId, tokenId);
            assertEq(extractors[i].stakedTimestamp, block.timestamp);
        }

        vm.warp(block.timestamp + 100);

        stakeExtractor(user, tokenId, maxStakeable - _amount);

        extractors = extractorRules.getExtractors();

        for (uint256 i = 0; i < _amount; i++) {
            assertEq(extractors[i].tokenId, tokenId);
            assertEq(extractors[i].stakedTimestamp, block.timestamp - 100);
        }

        for (uint256 i = _amount; i < maxStakeable; i++) {
            assertEq(extractors[i].tokenId, tokenId);
            assertEq(extractors[i].stakedTimestamp, block.timestamp);
        }
    }

    function test_getExtractorsTotalBoost(uint256 _amount) public {
        vm.assume(0 < _amount && _amount < maxStakeable - 1);

        address user = address(999);
        uint256 tokenId = 9;
        uint256 boost = 5e17;

        assertEq(extractorRules.getExtractorsTotalBoost(), 0);
        vm.prank(admin);
        extractorRules.setExtractorBoost(tokenId, boost);

        stakeExtractor(user, tokenId, _amount);

        assertEq(extractorRules.getExtractorsTotalBoost(), _amount * boost);

        vm.warp(block.timestamp + lifetime);

        stakeExtractor(user, tokenId, maxStakeable - _amount);

        assertEq(extractorRules.getExtractorsTotalBoost(), maxStakeable * boost);

        vm.warp(block.timestamp + 1);

        assertEq(extractorRules.getExtractorsTotalBoost(), (maxStakeable - _amount) * boost);
    }

    function test_getUserBoost(address _user, uint256 _tokenId, uint256 _amount) public {
        assertEq(extractorRules.getUserBoost(_user, extractorAddress, _tokenId, _amount), 0);
    }

    function test_getHarvesterBoost(uint256 _amount) public {
        vm.assume(0 < _amount && _amount < maxStakeable - 1);

        address user = address(999);
        uint256 tokenId = 9;
        uint256 boost = 5e17;

        assertEq(extractorRules.getHarvesterBoost(), Constant.ONE);
        vm.prank(admin);
        extractorRules.setExtractorBoost(tokenId, boost);

        stakeExtractor(user, tokenId, _amount);

        assertEq(extractorRules.getHarvesterBoost(), Constant.ONE + extractorRules.getExtractorsTotalBoost());

        vm.warp(block.timestamp + lifetime);

        stakeExtractor(user, tokenId, maxStakeable - _amount);

        assertEq(extractorRules.getHarvesterBoost(), Constant.ONE + extractorRules.getExtractorsTotalBoost());

        vm.warp(block.timestamp + 1);

        assertEq(extractorRules.getHarvesterBoost(), Constant.ONE + extractorRules.getExtractorsTotalBoost());
    }

    function test_setMaxStakeable() public {
        assertEq(extractorRules.maxStakeable(), maxStakeable);

        uint256 newMaxStakeable = 15;

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        extractorRules.setMaxStakeable(newMaxStakeable);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MaxStakeable(newMaxStakeable);
        extractorRules.setMaxStakeable(newMaxStakeable);

        assertEq(extractorRules.maxStakeable(), newMaxStakeable);
    }

    function test_setExtractorBoost(uint256 _boost) public {
        uint256 tokenId = 9;

        assertEq(extractorRules.extractorBoost(tokenId), 0);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        extractorRules.setExtractorBoost(tokenId, _boost);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ExtractorBoost(tokenId, _boost);
        extractorRules.setExtractorBoost(tokenId, _boost);

        assertEq(extractorRules.extractorBoost(tokenId), _boost);
    }

    function test_setExtractorAddress(address _extractorAddress) public {
        vm.assume(_extractorAddress != extractorAddress);

        assertEq(extractorRules.extractorAddress(), extractorAddress);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        extractorRules.setExtractorAddress(_extractorAddress);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ExtractorAddress(_extractorAddress);
        extractorRules.setExtractorAddress(_extractorAddress);

        assertEq(extractorRules.extractorAddress(), _extractorAddress);
    }

    function test_setExtractorLifetime(uint256 _lifetime) public {
        vm.assume(_lifetime != lifetime);

        assertEq(extractorRules.lifetime(), lifetime);

        bytes memory errorMsg = TestUtils.getAccessControlErrorMsg(address(this), extractorRules.SR_ADMIN());
        vm.expectRevert(errorMsg);
        extractorRules.setExtractorLifetime(_lifetime);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit Lifetime(_lifetime);
        extractorRules.setExtractorLifetime(_lifetime);

        assertEq(extractorRules.lifetime(), _lifetime);
    }
}

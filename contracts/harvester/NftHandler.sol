// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import '@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';

import './interfaces/INftHandler.sol';
import './interfaces/IHarvester.sol';
import './interfaces/IExtractorStakingRules.sol';

import './lib/Constant.sol';

contract NftHandler is INftHandler, AccessControlEnumerableUpgradeable, ERC1155HolderUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant NH_ADMIN = keccak256("NH_ADMIN");

    IHarvester public harvester;

    /// @dev maps NFT address to its config
    mapping(address => NftConfig) public allowedNfts;

    /// @dev Set of all allowed NFT addresses
    EnumerableSet.AddressSet private allAllowedNfts;

    /// @dev user => NFT address => tokenId => amount
    mapping (address => mapping(address => mapping(uint256 => uint256))) public stakedNfts;

    // user => boost
    mapping (address => uint256) public getUserBoost;

    event Staked(address indexed nft, uint256 tokenId, uint256 amount);
    event Unstaked(address indexed nft, uint256 tokenId, uint256 amount);
    event Replaced(address indexed nft, uint256 tokenId, uint256 amount, uint256 replacedSpotId);
    event NftConfigSet(address indexed _nft, NftConfig _nftConfig);

    modifier validateInput(address _nft, uint256 _amount) {
        if (_nft == address(0)) revert("InvalidNftAddress()");
        if (_amount == 0) revert("NothingToStake()");

        _;
    }

    modifier canStake(address _user, address _nft, uint256 _tokenId, uint256 _amount) {
        IStakingRules stakingRules = allowedNfts[_nft].stakingRules;

        if (address(stakingRules) != address(0)) {
            stakingRules.canStake(msg.sender, _nft, _tokenId, _amount);
        }

        _;
    }

    modifier canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount) {
        IStakingRules stakingRules = allowedNfts[_nft].stakingRules;

        if (address(stakingRules) != address(0)) {
            stakingRules.canUnstake(msg.sender, _nft, _tokenId, _amount);
        }

        _;
    }

    /// @dev Initialized by factory during deployment
    function init(
        address _admin,
        address _harvester,
        address[] memory _nfts,
        INftHandler.NftConfig[] memory _nftConfigs
    ) external initializer {
        _setRoleAdmin(NH_ADMIN, NH_ADMIN);
        _grantRole(NH_ADMIN, _admin);

        harvester = IHarvester(_harvester);

        if (_nfts.length != _nftConfigs.length) revert("InvalidData()");

        for (uint256 i = 0; i < _nfts.length; i++) {
            _setNftConfig(_nfts[i], _nftConfigs[i]);
        }

        __AccessControlEnumerable_init();
        __ERC1155Holder_init();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155ReceiverUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return
            ERC1155ReceiverUpgradeable.supportsInterface(interfaceId)
            || AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
    }

    function getAllAllowedNFTs() external view returns (address[] memory) {
        return allAllowedNfts.values();
    }

    function getAllAllowedNFTsLength() external view returns (uint256) {
        return allAllowedNfts.length();
    }

    function getStakingRules(address _nft) external view returns (address) {
        return address(allowedNfts[_nft].stakingRules);
    }

    function getSupportedInterface(address _nft) external view returns (Interfaces) {
        return allowedNfts[_nft].supportedInterface;
    }

    function getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) public view returns (uint256 boost) {
        IStakingRules stakingRules = allowedNfts[_nft].stakingRules;

        if (address(stakingRules) != address(0)) {
            boost = stakingRules.getUserBoost(_user, _nft, _tokenId, _amount);
        }
    }

    function getHarvesterTotalBoost() public view returns (uint256 boost) {
        boost = Constant.ONE;

        for (uint256 i = 0; i < allAllowedNfts.length(); i++) {
            address _nft = allAllowedNfts.at(i);

            IStakingRules stakingRules = allowedNfts[_nft].stakingRules;

            if (address(stakingRules) != address(0)) {
                boost = boost * stakingRules.getHarvesterBoost() / Constant.ONE;
            }
        }
    }

    function stakeNft(address _nft, uint256 _tokenId, uint256 _amount)
        public
        validateInput(_nft, _amount)
        canStake(msg.sender, _nft, _tokenId, _amount)
    {
        if (allowedNfts[_nft].supportedInterface == Interfaces.ERC721) {
            if (_amount != 1) revert("WrongAmountForERC721()");
            if (stakedNfts[msg.sender][_nft][_tokenId] != 0) revert("NftAlreadyStaked()");

            IERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);
        } else if (allowedNfts[_nft].supportedInterface == Interfaces.ERC1155) {
            IERC1155(_nft).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, bytes(""));
        } else {
            revert("NftNotAllowed()");
        }

        stakedNfts[msg.sender][_nft][_tokenId] += _amount;

        getUserBoost[msg.sender] += getNftBoost(msg.sender, _nft, _tokenId, _amount);
        harvester.updateNftBoost(msg.sender);

        emit Staked(_nft, _tokenId, _amount);
    }

    function unstakeNft(address _nft, uint256 _tokenId, uint256 _amount)
        external
        validateInput(_nft, _amount)
        canUnstake(msg.sender, _nft, _tokenId, _amount)
    {
        if (allowedNfts[_nft].supportedInterface == Interfaces.ERC721) {
            if (_amount != 1) revert("WrongAmountForERC721()");
            if (stakedNfts[msg.sender][_nft][_tokenId] != 1) revert("NftNotStaked()");

            IERC721(_nft).transferFrom(address(this), msg.sender, _tokenId);
        } else if (allowedNfts[_nft].supportedInterface == Interfaces.ERC1155) {
            IERC1155(_nft).safeTransferFrom(address(this), msg.sender, _tokenId, _amount, bytes(""));
        } else {
            revert("NftNotAllowed()");
        }

        uint256 staked = stakedNfts[msg.sender][_nft][_tokenId];
        if (_amount > staked) revert("AmountTooBig()");
        stakedNfts[msg.sender][_nft][_tokenId] = staked - _amount;

        getUserBoost[msg.sender] -= getNftBoost(msg.sender, _nft, _tokenId, _amount);
        harvester.updateNftBoost(msg.sender);

        emit Unstaked(_nft, _tokenId, _amount);
    }

    function replaceExtractor(address _nft, uint256 _tokenId, uint256 _amount, uint256 _replacedSpotId)
        external
        validateInput(_nft, _amount)
    {
        IExtractorStakingRules stakingRules = IExtractorStakingRules(address(allowedNfts[_nft].stakingRules));

        if (address(stakingRules) == address(0)) revert("StakingRulesRequired()");
        if (allowedNfts[_nft].supportedInterface != Interfaces.ERC1155) revert("MustBeERC1155()");

        (
            address user,
            uint256 replacedTokenId,
            uint256 replacedAmount
        ) = stakingRules.canReplace(msg.sender, _nft, _tokenId, _amount, _replacedSpotId);

        IERC1155(_nft).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, bytes(""));
        ERC1155Burnable(_nft).burn(address(this), replacedTokenId, replacedAmount);

        stakedNfts[user][_nft][replacedTokenId] -= replacedAmount;
        stakedNfts[msg.sender][_nft][_tokenId] += _amount;

        emit Replaced(_nft, _tokenId, _amount, _replacedSpotId);
    }

    // ADMIN

    function setNftConfig(address _nft, NftConfig memory _nftConfig) external onlyRole(NH_ADMIN) {
        _setNftConfig(_nft, _nftConfig);
    }

    function _setNftConfig(address _nft, NftConfig memory _nftConfig) internal {
        if (address(_nftConfig.stakingRules) != address(0)) {
            // it means we are adding _nft or updating its config
            // ignore return value in case we are just updating config
            allAllowedNfts.add(_nft);
        } else {
            if (!allAllowedNfts.remove(_nft)) revert("AlreadyDisallowed()");
            _nftConfig.supportedInterface = Interfaces.Unsupported;
        }

        allowedNfts[_nft] = _nftConfig;
        emit NftConfigSet(_nft, _nftConfig);
    }
}

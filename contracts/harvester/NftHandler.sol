// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol';

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

import '../interfaces/IHarvester.sol';
import '../interfaces/IStakingRules.sol';
import '../interfaces/IExtractorStakingRules.sol';

contract NftHandler is AccessControlEnumerable, ERC1155Holder {
    enum Interfaces { Unsupported, ERC721, ERC1155 }

    bytes32 public constant NFT_HANDLER_ADMIN_ROLE = keccak256("NFT_HANDLER_ADMIN_ROLE");

    struct NftConfig {
        Interfaces supportedInterface;
        /// @dev contract address which calcualtes boost for this NFT
        IStakingRules stakingRules;
    }

    IHarvester public harvester;

    /// @dev maps NFT address to its config
    mapping(address => NftConfig) public allowedNfts;

    /// @dev user => NFT address => tokenId => amount
    mapping (address => mapping(address => mapping(uint256 => uint256))) public stakedNfts;

    // user => boost
    mapping (address => uint256) public getUserBoost;

    event Staked(address indexed nft, uint256 tokenId, uint256 amount);
    event Unstaked(address indexed nft, uint256 tokenId, uint256 amount);
    event Replaced(address indexed nft, uint256 tokenId, uint256 amount, uint256 replacedSpotId);
    event NftConfigUpdate(address indexed _nft, NftConfig _nftConfig);

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

    constructor(address _admin) {
        _setRoleAdmin(NFT_HANDLER_ADMIN_ROLE, NFT_HANDLER_ADMIN_ROLE);
        _grantRole(NFT_HANDLER_ADMIN_ROLE, _admin);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Receiver, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function getStakingRules(address _nft) external view returns (address) {
        return address(allowedNfts[_nft].stakingRules);
    }

    function getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) public view returns (uint256 boost) {
        IStakingRules stakingRules = allowedNfts[_nft].stakingRules;

        if (address(stakingRules) != address(0)) {
            boost = stakingRules.getBoost(_user, _nft, _tokenId, _amount);
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
            uint256 replacedTokenId,
            uint256 replacedAmount
        ) = stakingRules.canReplace(msg.sender, _nft, _tokenId, _amount, _replacedSpotId);

        IERC1155(_nft).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, bytes(""));
        ERC1155Burnable(_nft).burn(address(this), replacedTokenId, replacedAmount);

        emit Replaced(_nft, _tokenId, _amount, _replacedSpotId);
    }

    // ADMIN

    function setNftConfig(address _nft, NftConfig memory _nftConfig) external onlyRole(NFT_HANDLER_ADMIN_ROLE) {
        allowedNfts[_nft] = _nftConfig;
        emit NftConfigUpdate(_nft, _nftConfig);
    }
}

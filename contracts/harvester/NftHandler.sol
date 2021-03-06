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

    /// @dev if `allowedNfts` is set for DEFAULT_ID as `tokenId`,
    ///      that value will be used as default for all collection,
    ///      unless specified differently
    uint256 public constant DEFAULT_ID = 69420e18;

    IHarvester public harvester;

    // 4 - Small Extractor
    // 5 - Medium Extractor
    // 6 - Large Extractor
    // 7 - Harvester Part

    /// @dev NFT address => tokenId => config
    mapping(address => mapping(uint256 => NftConfig)) public allowedNfts;

    /// @dev StakingRules => usage (number of contracts/tokens using given rules)
    mapping(address => uint256) public stakingRulesUsage;

    /// @dev Set of all registered StakingRules contracts
    EnumerableSet.AddressSet private allStakingRules;

    /// @dev user => NFT address => tokenId => amount
    mapping (address => mapping(address => mapping(uint256 => uint256))) public stakedNfts;

    // user => boost
    mapping (address => uint256) public getUserBoost;

    event Staked(address indexed nft, uint256 tokenId, uint256 amount);
    event Unstaked(address indexed nft, uint256 tokenId, uint256 amount);
    event Replaced(address indexed nft, uint256 tokenId, uint256 amount, uint256 replacedSpotId);
    event NftConfigSet(address indexed _nft, uint256 indexed _tokenId, NftConfig _nftConfig);

    modifier validateInput(address _nft, uint256 _amount) {
        if (_nft == address(0)) revert("InvalidNftAddress()");
        if (_amount == 0) revert("NothingToStake()");

        _;
    }

    modifier canStake(address _user, address _nft, uint256 _tokenId, uint256 _amount) {
        IStakingRules stakingRules = getStakingRules(_nft, _tokenId);

        if (address(stakingRules) != address(0)) {
            stakingRules.canStake(msg.sender, _nft, _tokenId, _amount);
        }

        _;
    }

    modifier canUnstake(address _user, address _nft, uint256 _tokenId, uint256 _amount) {
        IStakingRules stakingRules = getStakingRules(_nft, _tokenId);

        if (address(stakingRules) != address(0)) {
            stakingRules.canUnstake(msg.sender, _nft, _tokenId, _amount);
        }

        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /// @dev Initialized by factory during deployment
    function init(
        address _admin,
        address _harvester,
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        INftHandler.NftConfig[] memory _nftConfigs
    ) external initializer {
        __AccessControlEnumerable_init();
        __ERC1155Holder_init();

        _setRoleAdmin(NH_ADMIN, NH_ADMIN);
        _grantRole(NH_ADMIN, _admin);

        harvester = IHarvester(_harvester);

        if (_nfts.length != _nftConfigs.length) revert("InvalidData()");

        for (uint256 i = 0; i < _nfts.length; i++) {
            _setNftConfig(_nfts[i], _tokenIds[i], _nftConfigs[i]);
        }
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

    function getAllStakingRules() external view returns (address[] memory) {
        return allStakingRules.values();
    }

    function getAllStakingRulesLength() external view returns (uint256) {
        return allStakingRules.length();
    }

    function getStakingRules(address _nft, uint256 _tokenId) public view returns (IStakingRules) {
        IStakingRules stakingRules = allowedNfts[_nft][_tokenId].stakingRules;

        if (address(stakingRules) == address(0)) {
            return allowedNfts[_nft][DEFAULT_ID].stakingRules;
        } else {
            return stakingRules;
        }
    }

    function getSupportedInterface(address _nft, uint256 _tokenId) public view returns (Interfaces) {
        Interfaces supportedInterface = allowedNfts[_nft][_tokenId].supportedInterface;

        if (supportedInterface == Interfaces.Unsupported) {
            return allowedNfts[_nft][DEFAULT_ID].supportedInterface;
        } else {
            return supportedInterface;
        }
    }

    function getNftBoost(address _user, address _nft, uint256 _tokenId, uint256 _amount) public view returns (uint256 boost) {
        IStakingRules stakingRules = getStakingRules(_nft, _tokenId);

        if (address(stakingRules) != address(0)) {
            boost = stakingRules.getUserBoost(_user, _nft, _tokenId, _amount);
        }
    }

    function getHarvesterTotalBoost() public view returns (uint256 boost) {
        boost = Constant.ONE;

        for (uint256 i = 0; i < allStakingRules.length(); i++) {
            IStakingRules stakingRules = IStakingRules(allStakingRules.at(i));

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
        Interfaces supportedInterface = getSupportedInterface(_nft, _tokenId);

        if (supportedInterface == Interfaces.ERC721) {
            if (_amount != 1) revert("WrongAmountForERC721()");
            if (stakedNfts[msg.sender][_nft][_tokenId] != 0) revert("NftAlreadyStaked()");

            IERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);
        } else if (supportedInterface == Interfaces.ERC1155) {
            IERC1155(_nft).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, bytes(""));
        } else {
            revert("NftNotAllowed()");
        }

        stakedNfts[msg.sender][_nft][_tokenId] += _amount;

        getUserBoost[msg.sender] += getNftBoost(msg.sender, _nft, _tokenId, _amount);
        harvester.updateNftBoost(msg.sender);

        emit Staked(_nft, _tokenId, _amount);
    }

    function batchStakeNft(address[] memory _nft, uint256[] memory _tokenId, uint256[] memory _amount) external {
        if (_nft.length != _tokenId.length || _tokenId.length != _amount.length) revert("InvalidData()");

        uint256 len = _nft.length;

        for (uint256 i = 0; i < len; i++) {
            stakeNft(_nft[i], _tokenId[i], _amount[i]);
        }
    }

    function unstakeNft(address _nft, uint256 _tokenId, uint256 _amount)
        public
        validateInput(_nft, _amount)
        canUnstake(msg.sender, _nft, _tokenId, _amount)
    {
        Interfaces supportedInterface = getSupportedInterface(_nft, _tokenId);

        if (supportedInterface == Interfaces.ERC721) {
            if (_amount != 1) revert("WrongAmountForERC721()");
            if (stakedNfts[msg.sender][_nft][_tokenId] != 1) revert("NftNotStaked()");

            IERC721(_nft).transferFrom(address(this), msg.sender, _tokenId);
        } else if (supportedInterface == Interfaces.ERC1155) {
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

    function batchUnstakeNft(address[] memory _nft, uint256[] memory _tokenId, uint256[] memory _amount) external {
        if (_nft.length != _tokenId.length || _tokenId.length != _amount.length) revert("InvalidData()");

        uint256 len = _nft.length;

        for (uint256 i = 0; i < len; i++) {
            unstakeNft(_nft[i], _tokenId[i], _amount[i]);
        }
    }

    function replaceExtractor(address _nft, uint256 _tokenId, uint256 _amount, uint256 _replacedSpotId)
        external
        validateInput(_nft, _amount)
    {
        IExtractorStakingRules stakingRules = IExtractorStakingRules(address(getStakingRules(_nft, _tokenId)));

        if (address(stakingRules) == address(0)) revert("StakingRulesRequired()");
        if (getSupportedInterface(_nft, _tokenId) != Interfaces.ERC1155) revert("MustBeERC1155()");

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

    function setNftConfig(address _nft, uint256 _tokenId, NftConfig memory _nftConfig)
        external
        onlyRole(NH_ADMIN)
    {
        _setNftConfig(_nft, _tokenId, _nftConfig);
    }

    function _setNftConfig(address _nft, uint256 _tokenId, NftConfig memory _nftConfig) internal {
        address newStakingRules = address(_nftConfig.stakingRules);
        address oldStakingRules = address(allowedNfts[_nft][_tokenId].stakingRules);

        if (newStakingRules != oldStakingRules) {
            if (oldStakingRules == address(0)) { // add
                if (_nftConfig.supportedInterface == Interfaces.Unsupported) revert("WrongInterface()");

                allStakingRules.add(newStakingRules);
                stakingRulesUsage[newStakingRules]++;
            } else if (newStakingRules == address(0)) { // remove
                if (stakingRulesUsage[oldStakingRules] == 1) allStakingRules.remove(oldStakingRules);

                stakingRulesUsage[oldStakingRules]--;
                _nftConfig.supportedInterface = Interfaces.Unsupported;
            } else { // update
                if (_nftConfig.supportedInterface == Interfaces.Unsupported) revert("WrongInterface()");

                if (stakingRulesUsage[oldStakingRules] == 1) allStakingRules.remove(oldStakingRules);
                stakingRulesUsage[oldStakingRules]--;

                allStakingRules.add(newStakingRules);
                stakingRulesUsage[newStakingRules]++;
            }
        }

        allowedNfts[_nft][_tokenId] = _nftConfig;
        emit NftConfigSet(_nft, _tokenId, _nftConfig);
    }
}

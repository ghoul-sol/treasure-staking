// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import './interfaces/IMasterOfCoin.sol';
import './interfaces/IStream.sol';

/// wallet controlled by trusted team members. Admin role aka MASTER_OF_COIN_ADMIN_ROLE, as initialized during init()
/// to msg.sender can:
/// • MASTER_OF_COIN_ADMIN_ROLE, as initialized during init() to msg.sender:
/// • Add or remove streams, by calling addStream() and removeStream(), respectively.
/// • Increasing an active stream's ratePerSecond and totalRewards, by calling fundStream().
/// • Decrease an active stream's ratePerSecond and totalRewards, by calling defundStream().
/// • Modify a stream's startTimestamp, lastRewardTimestamp, endTimestamp and indirectly ratePerSecond, by calling
///   updateStreamTime().
/// • Enable/Disable registered stream addresses as callbacks, by calling setCallback().
/// • Withdraw an arbitrary magic token amount to an arbitrary address, by calling withdrawMagic().
/// • Set the magic token address to an arbitrary address, by calling setMagicToken().
contract MasterOfCoinV1 is IMasterOfCoin, Initializable, AccessControlEnumerableUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant MASTER_OF_COIN_ADMIN_ROLE = keccak256("MASTER_OF_COIN_ADMIN_ROLE");

    IERC20Upgradeable public magic;

    /// @notice stream address => CoinStream
    mapping (address => CoinStream) public streamConfig;

    /// @notice stream ID => stream address
    EnumerableSetUpgradeable.AddressSet internal streams;

    /// @notice stream address => bool
    mapping (address => bool) public callbackRegistry;

    modifier streamExists(address _stream) {
        require(streams.contains(_stream), "Stream does not exist");
        _;
    }

    modifier streamActive(address _stream) {
        require(streamConfig[_stream].endTimestamp > block.timestamp, "Stream ended");
        _;
    }

    modifier callbackStream(address _stream) {
        if (callbackRegistry[_stream]) IStream(_stream).preRateUpdate();
        _;
        if (callbackRegistry[_stream]) IStream(_stream).postRateUpdate();
    }

    event StreamAdded(address indexed stream, uint256 amount, uint256 startTimestamp, uint256 endTimestamp);
    event StreamTimeUpdated(address indexed stream, uint256 startTimestamp, uint256 endTimestamp);

    event StreamGrant(address indexed stream, address from, uint256 amount);
    event StreamFunded(address indexed stream, uint256 amount);
    event StreamDefunded(address indexed stream, uint256 amount);
    event StreamRemoved(address indexed stream);

    event RewardsPaid(address indexed stream, uint256 rewardsPaid, uint256 rewardsPaidInTotal);
    event Withdraw(address to, uint256 amount);
    event CallbackSet(address stream, bool value);

    function init(address _magic) external initializer {
        magic = IERC20Upgradeable(_magic);

        _setRoleAdmin(MASTER_OF_COIN_ADMIN_ROLE, MASTER_OF_COIN_ADMIN_ROLE);
        _grantRole(MASTER_OF_COIN_ADMIN_ROLE, msg.sender);

        __AccessControlEnumerable_init();
    }

    function requestRewards() public virtual returns (uint256 rewardsPaid) {
        CoinStream storage stream = streamConfig[msg.sender];

        rewardsPaid = getPendingRewards(msg.sender);

        if (rewardsPaid == 0 || magic.balanceOf(address(this)) < rewardsPaid) {
            return 0;
        }

        stream.paid += rewardsPaid;
        stream.lastRewardTimestamp = block.timestamp;

        // this should never happen but better safe than sorry
        require(stream.paid <= stream.totalRewards, "Rewards overflow");

        magic.safeTransfer(msg.sender, rewardsPaid);
        emit RewardsPaid(msg.sender, rewardsPaid, stream.paid);
    }

    function grantTokenToStream(address _stream, uint256 _amount)
        public
        virtual
        streamExists(_stream)
        streamActive(_stream)
        callbackStream(_stream)
    {
        _fundStream(_stream, _amount);

        magic.safeTransferFrom(msg.sender, address(this), _amount);
        emit StreamGrant(_stream, msg.sender, _amount);
    }

    function getStreams() external view virtual returns (address[] memory) {
        return streams.values();
    }

    function getStreamConfig(address _stream) external view virtual returns (CoinStream memory) {
        return streamConfig[_stream];
    }

    function getGlobalRatePerSecond() external view virtual returns (uint256 globalRatePerSecond) {
        uint256 len = streams.length();
        for (uint256 i = 0; i < len; i++) {
            globalRatePerSecond += getRatePerSecond(streams.at(i));
        }
    }

    function getRatePerSecond(address _stream) public view virtual returns (uint256 ratePerSecond) {
        CoinStream storage stream = streamConfig[_stream];

        if (stream.startTimestamp < block.timestamp && block.timestamp < stream.endTimestamp) {
            ratePerSecond = stream.ratePerSecond;
        }
    }

    function getPendingRewards(address _stream) public view virtual returns (uint256 pendingRewards) {
        CoinStream storage stream = streamConfig[_stream];

        uint256 paid = stream.paid;
        uint256 totalRewards = stream.totalRewards;
        uint256 lastRewardTimestamp = stream.lastRewardTimestamp;

        if (block.timestamp >= stream.endTimestamp) {
            // stream ended
            pendingRewards = totalRewards - paid;
        } else if (block.timestamp > lastRewardTimestamp) {
            // stream active
            uint256 secondsFromLastPull = block.timestamp - lastRewardTimestamp;
            pendingRewards = secondsFromLastPull * stream.ratePerSecond;

            // in case of rounding error, make sure that paid + pending rewards is never more than totalRewards
            if (paid + pendingRewards > totalRewards) {
                pendingRewards = totalRewards - paid;
            }
        }
    }

    function _fundStream(address _stream, uint256 _amount) internal virtual {
        CoinStream storage stream = streamConfig[_stream];

        uint256 secondsToEnd = stream.endTimestamp - stream.lastRewardTimestamp;
        uint256 rewardsLeft = secondsToEnd * stream.ratePerSecond;
        stream.ratePerSecond = (rewardsLeft + _amount) / secondsToEnd;
        stream.totalRewards += _amount;
    }

    // ADMIN

    /// @param _stream address of the contract that gets rewards
    /// @param _totalRewards amount of MAGIC that should be distributed in total
    /// @param _startTimestamp when MAGIC stream should start
    /// @param _endTimestamp when MAGIC stream should end
    /// @param _callback should callback be used (if you don't know, set false)
    function addStream(
        address _stream,
        uint256 _totalRewards,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        bool _callback
    ) external virtual onlyRole(MASTER_OF_COIN_ADMIN_ROLE) {
        require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
        require(!streams.contains(_stream), "Stream for address already exists");

        if (streams.add(_stream)) {
            streamConfig[_stream] = CoinStream({
                totalRewards: _totalRewards,
                /// @dev if stream lasts only for one second, it won't show in `getGlobalRatePerSecond`
                startTimestamp: _startTimestamp,
                endTimestamp: _endTimestamp,
                lastRewardTimestamp: _startTimestamp,
                ratePerSecond: _totalRewards / (_endTimestamp - _startTimestamp),
                paid: 0
            });
            emit StreamAdded(_stream, _totalRewards, _startTimestamp, _endTimestamp);

            setCallback(_stream, _callback);
        }
    }

    function fundStream(address _stream, uint256 _amount)
        external
        virtual
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
        callbackStream(_stream)
    {
        _fundStream(_stream, _amount);
        emit StreamFunded(_stream, _amount);
    }

    function defundStream(address _stream, uint256 _amount)
        external
        virtual
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
        callbackStream(_stream)
    {
        CoinStream storage stream = streamConfig[_stream];

        uint256 secondsToEnd = stream.endTimestamp - stream.lastRewardTimestamp;
        uint256 rewardsLeft = secondsToEnd * stream.ratePerSecond;

        require(_amount <= rewardsLeft, "Reduce amount too large, rewards already paid");

        stream.ratePerSecond = (rewardsLeft - _amount) / secondsToEnd;
        stream.totalRewards -= _amount;

        emit StreamDefunded(_stream, _amount);
    }

    function updateStreamTime(address _stream, uint256 _startTimestamp, uint256 _endTimestamp)
        external
        virtual
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        callbackStream(_stream)
    {
        CoinStream storage stream = streamConfig[_stream];

        if (_startTimestamp > 0) {
            require(_startTimestamp > block.timestamp, "startTimestamp cannot be in the past");

            stream.startTimestamp = _startTimestamp;
            stream.lastRewardTimestamp = _startTimestamp;
        }

        if (_endTimestamp > 0) {
            require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
            require(_endTimestamp > block.timestamp, "Cannot end rewards in the past");

            stream.endTimestamp = _endTimestamp;
        }

        stream.ratePerSecond = (stream.totalRewards - stream.paid) / (stream.endTimestamp - stream.lastRewardTimestamp);

        emit StreamTimeUpdated(_stream, _startTimestamp, _endTimestamp);
    }

    function removeStream(address _stream)
        external
        virtual
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        callbackStream(_stream)
    {
        if (streams.remove(_stream)) {
            delete streamConfig[_stream];
            emit StreamRemoved(_stream);
        }
    }

    function setCallback(address _stream, bool _value)
        public
        virtual
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        callbackStream(_stream)
    {
        callbackRegistry[_stream] = _value;
        emit CallbackSet(_stream, _value);
    }

    function withdrawMagic(address _to, uint256 _amount) external virtual onlyRole(MASTER_OF_COIN_ADMIN_ROLE) {
        magic.safeTransfer(_to, _amount);
        emit Withdraw(_to, _amount);
    }

    function setMagicToken(address _magic) external virtual onlyRole(MASTER_OF_COIN_ADMIN_ROLE) {
        magic = IERC20Upgradeable(_magic);
    }
}

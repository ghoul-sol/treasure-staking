// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import 'hardhat/console.sol';

contract MasterOfCoin is AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 public constant MASTER_OF_COIN_ADMIN_ROLE = keccak256("MASTER_OF_COIN_ADMIN_ROLE");

    struct CoinStream {
        uint256 totalRewards;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 lastRewardTimestamp;
        uint256 ratePerSecond;
        uint256 paid;
    }

    IERC20 public magic;

    /// @notice contract => CoinStream
    mapping (address => CoinStream) public streamConfig;

    /// @notice stream ID => stream address
    EnumerableSet.AddressSet private streams;

    modifier streamExists(address _stream) {
        require(streams.contains(_stream), "Stream does not exist");
        _;
    }

    modifier streamActive(address _stream) {
        require(streamConfig[_stream].endTimestamp > block.timestamp, "Stream ended");
        _;
    }

    event StreamAdded(address indexed stream, uint256 amount, uint256 startTimestamp, uint256 endTimestamp);
    event StreamTimeUpdated(address indexed stream, uint256 startTimestamp, uint256 endTimestamp);

    event StreamGrant(address indexed stream, address from, uint256 amount);
    event StreamFunded(address indexed stream, uint256 amount);
    event StreamDefunded(address indexed stream, uint256 amount);
    event StreamRemoved(address indexed stream);

    event RewardsPaid(address indexed stream, uint256 rewardsPaid, uint256 rewardsPaidInTotal);
    event Withdraw(address to, uint256 amount);

    function init(address _magic) external {
        require(address(magic) == address(0), "Already initialized");

        magic = IERC20(_magic);

        _setRoleAdmin(MASTER_OF_COIN_ADMIN_ROLE, MASTER_OF_COIN_ADMIN_ROLE);
        _grantRole(MASTER_OF_COIN_ADMIN_ROLE, msg.sender);
    }

    function requestRewards() public returns (uint256 rewardsPaid) {
        CoinStream storage stream = streamConfig[msg.sender];

        rewardsPaid = getPendingRewards(msg.sender);
        console.log('rewardsPaid', rewardsPaid);

        if (rewardsPaid == 0 || magic.balanceOf(address(this)) < rewardsPaid) {
            return 0;
        }


        stream.paid += rewardsPaid;
        stream.lastRewardTimestamp = block.timestamp;
        console.log('stream.paid', stream.paid);

        // this should never happen but better safe than sorry
        require(stream.paid <= stream.totalRewards, "Rewards overflow");

        magic.safeTransfer(msg.sender, rewardsPaid);
        emit RewardsPaid(msg.sender, rewardsPaid, stream.paid);
    }

    function grantTokenToStream(address _stream, uint256 _amount) public streamExists(_stream) streamActive(_stream) {
        _fundStream(_stream, _amount);

        magic.safeTransferFrom(msg.sender, address(this), _amount);
        emit StreamGrant(_stream, msg.sender, _amount);
    }

    function getStreams() external view returns (address[] memory) {
        return streams.values();
    }

    function getGlobalRatePerSecond() external view returns (uint256 globalRatePerSecond) {
        uint256 len = streams.length();
        for (uint256 i = 0; i < len; i++) {
            globalRatePerSecond += getRatePerSecond(streams.at(i));
        }
    }

    function getRatePerSecond(address _stream) public view returns (uint256 ratePerSecond) {
        CoinStream storage stream = streamConfig[_stream];

        if (stream.startTimestamp < block.timestamp && block.timestamp < stream.endTimestamp) {
            ratePerSecond = stream.ratePerSecond;
        }
    }

    function getPendingRewards(address _stream) public view returns (uint256 pendingRewards) {
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

    function _fundStream(address _stream, uint256 _amount) internal {
        CoinStream storage stream = streamConfig[_stream];

        uint256 secondsToEnd = stream.endTimestamp - stream.lastRewardTimestamp;
        uint256 rewardsLeft = secondsToEnd * stream.ratePerSecond;
        stream.ratePerSecond = (rewardsLeft + _amount) / secondsToEnd;
        stream.totalRewards += _amount;
    }

    // ADMIN

    function addStream(
        address _stream,
        uint256 _totalRewards,
        uint256 _startTimestamp,
        uint256 _endTimestamp
    ) external onlyRole(MASTER_OF_COIN_ADMIN_ROLE) {
        require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
        require(!streams.contains(_stream), "Stream for address already exists");

        if (streams.add(_stream)) {
            streamConfig[_stream] = CoinStream({
                totalRewards: _totalRewards,
                startTimestamp: _startTimestamp,
                endTimestamp: _endTimestamp,
                lastRewardTimestamp: _startTimestamp,
                ratePerSecond: _totalRewards / (_endTimestamp - _startTimestamp),
                paid: 0
            });
            emit StreamAdded(_stream, _totalRewards, _startTimestamp, _endTimestamp);
        }
    }

    function fundStream(address _stream, uint256 _amount)
        external
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
    {
        _fundStream(_stream, _amount);
        emit StreamFunded(_stream, _amount);
    }

    function defundStream(address _stream, uint256 _amount)
        external
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
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
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
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

    function removeStream(address _stream) external onlyRole(MASTER_OF_COIN_ADMIN_ROLE) streamExists(_stream) {
        if (streams.remove(_stream)) {
            delete streamConfig[_stream];
            emit StreamRemoved(_stream);
        }
    }

    function withdrawMagic(address _to, uint256 _amount) external onlyRole(MASTER_OF_COIN_ADMIN_ROLE) {
        magic.safeTransfer(_to, _amount);
        emit Withdraw(_to, _amount);
    }
}

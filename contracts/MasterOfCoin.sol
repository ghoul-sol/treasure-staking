// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import './MasterOfCoinV1.sol';

contract MasterOfCoin is MasterOfCoinV1 {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint256 public constant PRECISION = 1e18;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function _fundStream(address _stream, uint256 _amount) internal virtual override {
        CoinStream storage stream = streamConfig[_stream];

        uint256 secondsToEnd = stream.endTimestamp - stream.lastRewardTimestamp;
        uint256 rewardsLeft = secondsToEnd * stream.ratePerSecond;
        stream.ratePerSecond = (rewardsLeft + _amount) * PRECISION / secondsToEnd / PRECISION;
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
    ) external virtual override onlyRole(MASTER_OF_COIN_ADMIN_ROLE) {
        require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
        require(!streams.contains(_stream), "Stream for address already exists");

        if (streams.add(_stream)) {
            streamConfig[_stream] = CoinStream({
                totalRewards: _totalRewards,
                startTimestamp: _startTimestamp,
                endTimestamp: _endTimestamp,
                lastRewardTimestamp: _startTimestamp,
                ratePerSecond: _totalRewards * PRECISION / (_endTimestamp - _startTimestamp) / PRECISION,
                paid: 0
            });
            emit StreamAdded(_stream, _totalRewards, _startTimestamp, _endTimestamp);

            setCallback(_stream, _callback);
        }
    }

    function defundStream(address _stream, uint256 _amount)
        external
        virtual
        override
        onlyRole(MASTER_OF_COIN_ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
        callbackStream(_stream)
    {
        CoinStream storage stream = streamConfig[_stream];

        uint256 secondsToEnd = stream.endTimestamp - stream.lastRewardTimestamp;
        uint256 rewardsLeft = secondsToEnd * stream.ratePerSecond;

        require(_amount <= rewardsLeft, "Reduce amount too large, rewards already paid");

        stream.ratePerSecond = (rewardsLeft - _amount) * PRECISION / secondsToEnd / PRECISION;
        stream.totalRewards -= _amount;

        emit StreamDefunded(_stream, _amount);
    }

    function updateStreamTime(address _stream, uint256 _startTimestamp, uint256 _endTimestamp)
        external
        virtual
        override
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

        stream.ratePerSecond =
            (stream.totalRewards - stream.paid)
             * PRECISION
             / (stream.endTimestamp - stream.lastRewardTimestamp)
             / PRECISION;

        emit StreamTimeUpdated(_stream, _startTimestamp, _endTimestamp);
    }
}

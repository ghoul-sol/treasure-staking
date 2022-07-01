// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface IMasterOfCoin {
    struct CoinStream {
        uint256 totalRewards;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 lastRewardTimestamp;
        uint256 ratePerSecond;
        uint256 paid;
    }

    function requestRewards() external returns (uint256 rewardsPaid);

    function grantTokenToStream(address _stream, uint256 _amount) external;

    function getStreams() external view returns (address[] memory);

    function getStreamConfig(address _stream) external view returns (CoinStream memory);

    function getGlobalRatePerSecond() external view returns (uint256 globalRatePerSecond);

    function getRatePerSecond(address _stream) external view returns (uint256 ratePerSecond);

    function getPendingRewards(address _stream) external view returns (uint256 pendingRewards);
}

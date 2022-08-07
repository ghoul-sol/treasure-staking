// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '../interfaces/INftHandler.sol';

import "./StakingRulesBase.sol";

contract PartsStakingRules is StakingRulesBase {
    uint256 public staked;
    uint256 public maxStakeableTotal;
    uint256 public maxStakeablePerUser;
    uint256 public boostFactor;

    mapping(address => uint256) public getAmountStaked;

    event MaxStakeableTotal(uint256 maxStakeableTotal);
    event MaxStakeablePerUser(uint256 maxStakeablePerUser);
    event BoostFactor(uint256 boostFactor);

    modifier validateInput(address _user, uint256 _amount) {
        require(_user != address(0), "ZeroAddress()");
        require(_amount > 0, "ZeroAmount()");

        _;
    }

    function init(
        address _admin,
        address _harvesterFactory,
        uint256 _maxStakeableTotal,
        uint256 _maxStakeablePerUser,
        uint256 _boostFactor
    ) external initializer {
        _initStakingRulesBase(_admin, _harvesterFactory);

        _setMaxStakeableTotal(_maxStakeableTotal);
        _setMaxStakeablePerUser(_maxStakeablePerUser);
        _setBoostFactor(_boostFactor);
    }

    /// @inheritdoc IStakingRules
    function getUserBoost(address, address, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IStakingRules
    function getHarvesterBoost() external view returns (uint256) {
        // quadratic function in the interval: [1, (1 + boost_factor)] based on number of parts staked.
        // exhibits diminishing returns on boosts as more parts are added
        // num_parts: number of harvester parts
        // max_parts: number of parts to achieve max boost
        // boost_factor: the amount of boost you want to apply to parts
        // default is 1 = 100% boost (2x) if num_parts = max_parts
        // # weight for additional parts has  diminishing gains
        // n = num_parts
        // return 1 + (2*n - n**2/max_parts) / max_parts * boost_factor

        uint256 n = staked * Constant.ONE;
        uint256 maxParts = maxStakeableTotal * Constant.ONE;
        if (maxParts == 0) return Constant.ONE;
        uint256 boost = boostFactor;
        return Constant.ONE + (2 * n - n ** 2 / maxParts) * boost / maxParts;
    }

    function _processStake(address _user, address, uint256, uint256 _amount)
        internal
        override
        validateInput(_user, _amount)
    {
        uint256 stakedCache = staked;
        if (stakedCache + _amount > maxStakeableTotal) revert("MaxStakeable()");
        staked = stakedCache + _amount;

        uint256 amountStakedCache = getAmountStaked[_user];
        if (amountStakedCache + _amount > maxStakeablePerUser) revert("MaxStakeablePerUser()");
        getAmountStaked[_user] = amountStakedCache + _amount;
    }

    function _processUnstake(address _user, address, uint256, uint256 _amount)
        internal
        override
        validateInput(_user, _amount)
    {
        staked -= _amount;
        getAmountStaked[_user] -= _amount;

        // require that user cap is above MAGIC deposit amount after unstake
        if (INftHandler(msg.sender).harvester().isMaxUserGlobalDeposit(_user)) {
            revert("MinUserGlobalDeposit()");
        }
    }

    // ADMIN

    function setMaxStakeableTotal(uint256 _maxStakeableTotal) external onlyRole(SR_ADMIN) {
        _setMaxStakeableTotal(_maxStakeableTotal);
    }

    function setMaxStakeablePerUser(uint256 _maxStakeablePerUser) external onlyRole(SR_ADMIN) {
        _setMaxStakeablePerUser(_maxStakeablePerUser);
    }

    function setBoostFactor(uint256 _boostFactor) external onlyRole(SR_ADMIN) {
        nftHandler.harvester().callUpdateRewards();

        _setBoostFactor(_boostFactor);
    }

    function _setMaxStakeableTotal(uint256 _maxStakeableTotal) internal {
        maxStakeableTotal = _maxStakeableTotal;
        emit MaxStakeableTotal(_maxStakeableTotal);
    }

    function _setMaxStakeablePerUser(uint256 _maxStakeablePerUser) internal {
        maxStakeablePerUser = _maxStakeablePerUser;
        emit MaxStakeablePerUser(_maxStakeablePerUser);
    }

    function _setBoostFactor(uint256 _boostFactor) internal {
        boostFactor = _boostFactor;
        emit BoostFactor(_boostFactor);
    }
}

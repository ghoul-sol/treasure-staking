// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

interface IUniswapV2Pair {
    function totalSupply() external view returns (uint);
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IMiniChefV2 {
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, int256 rewardDebt);
}

interface IAtlasMine {
    enum Lock { twoWeeks, oneMonth, threeMonths, sixMonths, twelveMonths }

    function magic() external view returns (IERC20);
    function getAllUserDepositIds(address _user) external view returns (uint256[] memory);
    function userInfo(address _user, uint256 _depositId) external view virtual returns (
        uint256 originalDepositAmount,
        uint256 depositAmount,
        uint256 lpAmount,
        uint256 lockedUntil,
        uint256 vestingLastUpdate,
        int256 rewardDebt,
        Lock lock);
    function getLockBoost(Lock _lock) external pure returns (uint256 boost, uint256 timelock);
    function ONE() external pure returns (uint256);
}

interface IHarvester {
    function getUserGlobalDeposit(address _user) external view returns (uint256 globalDepositAmount, uint256 globalLockLpAmount, uint256 globalLpAmount, int256 globalRewardDebt);
}

interface IHarvesterFactory {
    function getAllHarvesters() external view returns (address[] memory);
}

contract TreasureDAO is ERC20 {
    uint256 public constant PID = 13;

    IAtlasMine public atlasMine;
    IUniswapV2Pair public sushiLP;
    IMiniChefV2 public miniChefV2;
    IHarvesterFactory public harvesterFactory;

    constructor(address _atlasMine, address _sushiLP, address _miniChefV2, address _harvesterFactory) ERC20("Treasure DAO Governance", "gMAGIC") {
        atlasMine = IAtlasMine(_atlasMine);
        sushiLP = IUniswapV2Pair(_sushiLP);
        miniChefV2 = IMiniChefV2(_miniChefV2);
        harvesterFactory = IHarvesterFactory(_harvesterFactory);
    }

    function totalSupply() public view override returns (uint256) {
        return atlasMine.magic().totalSupply();
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return getMineBalance(_account) + getLPBalance(_account) + getHarvesterBalance(_account);
    }

    function getMineBalance(address _account) public view returns (uint256 userMineBalance) {
        uint256[] memory allUserDepositIds = atlasMine.getAllUserDepositIds(_account);
        uint256 len = allUserDepositIds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 depositId = allUserDepositIds[i];
            (, uint256 depositAmount,,,,, IAtlasMine.Lock lock) = atlasMine.userInfo(_account, depositId);
            (uint256 lockBoost, ) = atlasMine.getLockBoost(lock);
            uint256 lpAmount = depositAmount + depositAmount * lockBoost / atlasMine.ONE();
            userMineBalance += lpAmount;
        }
    }

    function getLPBalance(address _account) public view returns (uint256) {
        (uint256 liquidity, ) = miniChefV2.userInfo(PID, _account);
        (uint112 _reserve0, uint112 _reserve1,) = sushiLP.getReserves();

        if (address(atlasMine.magic()) == sushiLP.token0()) {
            return _reserve0 * liquidity / sushiLP.totalSupply();
        } else {
            return _reserve1 * liquidity / sushiLP.totalSupply();
        }
    }

    function getHarvesterBalance(address _account) public view returns (uint256 harvesterBalance) {
        address[] memory harvesters = harvesterFactory.getAllHarvesters();
        uint256 len = harvesters.length;
        for (uint256 i = 0; i < len; i++) {
            (uint256 globalDepositAmount,,,) = IHarvester(harvesters[i]).getUserGlobalDeposit(_account);
            harvesterBalance += globalDepositAmount;
        }
    }

    function _beforeTokenTransfer(address, address, uint256) internal pure override {
        revert("Non-transferable");
    }
}

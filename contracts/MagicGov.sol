// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';

import './interfaces/IUniswapV2Pair.sol';
import './interfaces/IMiniChefV2.sol';
import './harvester/interfaces/IHarvester.sol';
import './harvester/interfaces/IHarvesterFactory.sol';
import './AtlasMine.sol';

contract TreasureDAO is ERC20 {
    uint256 public constant PID = 13;

    AtlasMine public atlasMine;
    IUniswapV2Pair public sushiLP;
    IMiniChefV2 public miniChefV2;
    IHarvesterFactory public harvesterFactory;

    constructor(address _atlasMine, address _sushiLP, address _miniChefV2, address _harvesterFactory) ERC20("Treasure DAO Governance", "gMAGIC") {
        atlasMine = AtlasMine(_atlasMine);
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
            (, uint256 depositAmount,,,,, AtlasMine.Lock lock) = atlasMine.userInfo(_account, depositId);
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

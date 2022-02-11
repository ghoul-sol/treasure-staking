import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const sushiLP = "0xB7E50106A5bd3Cf21AF210A755F9C8740890A8c9";
    const miniChefV2 = "0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3";
    const atlasMine = "0xA0A89db1C899c49F98E6326b764BAFcf167fC2CE"

    await deploy('TreasureDAO', {
      from: deployer,
      log: true,
      args: [atlasMine, sushiLP, miniChefV2]
    })
};
export default func;
func.tags = ['magicGov'];

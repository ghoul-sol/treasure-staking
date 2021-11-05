import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const sushiLP = "0xB7E50106A5bd3Cf21AF210A755F9C8740890A8c9";
    const lpRewards = "0x73EB8b2b235F7957f830ea66ABE433D9EED9f0E3";
    await deploy('TreasureDAO', {
      from: deployer,
      log: true,
      args: [(await deployments.get('TreasuryMine')).address, sushiLP, lpRewards]
    })
};
export default func;
func.tags = ['magicGov'];
func.dependencies = ['treasuryMine']

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicToken = '';
    const lpToken = '';
    await deploy('TreasuryStake', {
      from: deployer,
      log: true,
      args: [magicToken, lpToken]
    })
};
export default func;
func.tags = ['treasuryStake'];

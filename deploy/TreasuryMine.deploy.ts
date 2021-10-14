import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magic = await deploy('ERC20Mintable', {
      from: deployer,
      log: true
    })
    const magicToken = magic.address;
    const newOwner = deployer;
    await deploy('TreasuryMine', {
      from: deployer,
      log: true,
      args: [magicToken, (await deployments.get('TreasuryStake')).address, newOwner]
    })
};
export default func;
func.tags = ['treasuryMine'];
func.dependencies = ['treasuryStake']

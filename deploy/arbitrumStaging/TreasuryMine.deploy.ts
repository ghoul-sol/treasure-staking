import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const newOwner = deployer;
    const magicArbitrum = "0xfab95915359bdCa523c0EFe55e73B30b77897e1f";
    await deploy('TreasuryMine', {
      from: deployer,
      log: true,
      args: [magicArbitrum, (await deployments.get('TreasuryStake')).address, newOwner]
    })
};
export default func;
func.tags = ['treasuryMine'];
func.dependencies = ['treasuryStake']

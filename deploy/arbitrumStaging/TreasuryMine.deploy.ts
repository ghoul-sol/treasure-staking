import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const newOwner = deployer;
    const magicArbitrum = "0x86083653fef09AB89BEC7dA3815dD76AF9bCc006";
    await deploy('TreasuryMine', {
      from: deployer,
      log: true,
      args: [magicArbitrum, (await deployments.get('TreasuryStake')).address, newOwner]
    })
};
export default func;
func.tags = ['treasuryMine'];
func.dependencies = ['treasuryStake']

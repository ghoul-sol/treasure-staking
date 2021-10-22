import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
    const newOwner = "0x3D210e741cDeDeA81efCd9711Ce7ef7FEe45684B";
    await deploy('TreasuryMine', {
      from: deployer,
      log: true,
      args: [magicArbitrum, (await deployments.get('TreasuryStake')).address, newOwner]
    })
};
export default func;
func.tags = ['treasuryMine'];
func.dependencies = ['treasuryStake']

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
    const treasuresArbitrum = "0xEBba467eCB6b21239178033189CeAE27CA12EaDf";
    await deploy('TreasuryStake', {
      from: deployer,
      log: true,
      args: [magicArbitrum, treasuresArbitrum]
    })
};
export default func;
func.tags = ['treasuryStake'];

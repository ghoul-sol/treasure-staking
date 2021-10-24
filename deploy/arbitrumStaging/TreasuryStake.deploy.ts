import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0x86083653fef09AB89BEC7dA3815dD76AF9bCc006";
    const treasuresArbitrum = "0x4294Df31f34E6F376DFbD0CAe01917F68Be3c240";
    await deploy('TreasuryStake', {
      from: deployer,
      log: true,
      args: [magicArbitrum, treasuresArbitrum]
    })
};
export default func;
func.tags = ['treasuryStake'];

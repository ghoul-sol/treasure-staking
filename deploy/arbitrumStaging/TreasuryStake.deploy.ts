import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0xfab95915359bdCa523c0EFe55e73B30b77897e1f";
    const treasuresArbitrum = "0xFb5799C12C58b4494497b3e7eA3a58def1311517";
    await deploy('TreasuryStake', {
      from: deployer,
      log: true,
      args: [magicArbitrum, treasuresArbitrum]
    })
};
export default func;
func.tags = ['treasuryStake'];

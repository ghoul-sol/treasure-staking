import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicToken = await deploy('ERC20Mintable', {
      from: deployer,
      log: true
    })
    const treasure = await deploy('ERC721Mintable', {
      from: deployer,
      log: true
    })
    await deploy('TreasuryStake', {
      from: deployer,
      log: true,
      args: [magicToken.address, treasure.address]
    })
};
export default func;
func.tags = ['treasuryStake'];

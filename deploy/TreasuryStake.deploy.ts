import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicToken = (await deployments.get("ERC20Mintable")).address;
    const treasure = await deploy('ERC721Mintable', {
      from: deployer,
      log: true
    })
    const lpToken = treasure.address;
    await deploy('TreasuryStake', {
      from: deployer,
      log: true,
      args: [magicToken, lpToken]
    })
};
export default func;
func.tags = ['treasuryStake'];

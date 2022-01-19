import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
    const newOwner = "0x3D210e741cDeDeA81efCd9711Ce7ef7FEe45684B";

    await deploy('MasterOfCoin', {
      from: deployer,
      log: true,
      proxy: {
        owner: newOwner,
        proxyContract: "EIP173Proxy",
        execute: {
          methodName: "init",
          args: [magicArbitrum]
        }
      }
    })

    if(await read('MasterOfCoin', 'owner') != newOwner) {
      await execute(
        'MasterOfCoin',
        { from: deployer, log: true },
        'transferOwnership',
        newOwner
      );
    }
};
export default func;
func.tags = ['MasterOfCoin'];
// func.dependencies = ['treasuryStake']

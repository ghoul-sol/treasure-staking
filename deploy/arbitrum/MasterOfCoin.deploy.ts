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
        execute: {
          init: {
            methodName: "init",
            args: [magicArbitrum]
          }
        }
      }
    })

    const MASTER_OF_COIN_ADMIN_ROLE = await read('MasterOfCoin', 'MASTER_OF_COIN_ADMIN_ROLE');

    if(!(await read('MasterOfCoin', 'hasRole', MASTER_OF_COIN_ADMIN_ROLE, newOwner))) {
      await execute(
        'MasterOfCoin',
        { from: deployer, log: true },
        'grantRole',
        MASTER_OF_COIN_ADMIN_ROLE,
        newOwner
      );
    }
};
export default func;
func.tags = ['MasterOfCoin'];

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
    const newOwner = "0x3D210e741cDeDeA81efCd9711Ce7ef7FEe45684B";
    const masterOfCoin = (await deployments.get("MasterOfCoin")).address;

    await deploy('AtlasMine', {
      from: deployer,
      log: true,
      proxy: {
        execute: {
          methodName: "init",
          args: [magicArbitrum, masterOfCoin]
        }
      }
    })

    const ATLAS_MINE_ADMIN_ROLE = await read('AtlasMine', 'ATLAS_MINE_ADMIN_ROLE');

    if(!(await read('AtlasMine', 'hasRole', ATLAS_MINE_ADMIN_ROLE, newOwner))) {
      await execute(
        'AtlasMine',
        { from: deployer, log: true },
        'grantRole',
        ATLAS_MINE_ADMIN_ROLE,
        newOwner
      );
    }
};
export default func;
func.tags = ['AtlasMine'];
func.dependencies = ['MasterOfCoin']

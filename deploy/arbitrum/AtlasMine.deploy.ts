import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();

    const magicArbitrum = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
    const newOwner = "0x3D210e741cDeDeA81efCd9711Ce7ef7FEe45684B";

    const treasure = "0x6333F38F98f5c46dA6F873aCbF25DCf8748DDc2c";
    const legion = "0x96F791C0C11bAeE97526D5a9674494805aFBEc1c";
    const legionMetadataStore = "0x253dC801B38C79CcBFcECFDB2f5Bb5277c227537";

    await deploy('AtlasMine', {
      from: deployer,
      log: true,
      proxy: {
        execute: {
          init: {
            methodName: "init",
            args: [magicArbitrum, (await deployments.get("MasterOfCoin")).address]
          }
        }
      }
    })

    if(await read('AtlasMine', 'treasure') != treasure) {
      await execute(
        'AtlasMine',
        { from: deployer, log: true },
        'setTreasure',
        treasure
      );
    }

    if(await read('AtlasMine', 'legion') != legion) {
      await execute(
        'AtlasMine',
        { from: deployer, log: true },
        'setLegion',
        legion
      );
    }

    if(await read('AtlasMine', 'legionMetadataStore') != legionMetadataStore) {
      await execute(
        'AtlasMine',
        { from: deployer, log: true },
        'setLegionMetadataStore',
        legionMetadataStore
      );
    }

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

    // setup MasterOfCoin stream
    // if(streamConfig.totalRewards.eq(0)) {
    //   const totalRewards = ethers.utils.parseEther('10000');
    //   let ms = Date.now();
    //   const startTimestamp = Math.floor(ms / 1000 + 20);
    //   const endTimestamp = startTimestamp + 60 * 60 * 24 * 7;
    //   const callback = false;
    //
    //   await execute(
    //     'MasterOfCoin',
    //     { from: deployer, log: true },
    //     'addStream',
    //     atlasMine.address,
    //     totalRewards,
    //     startTimestamp,
    //     endTimestamp,
    //     callback
    //   );
    // }
};
export default func;
func.tags = ['AtlasMine'];
func.dependencies = ['MasterOfCoin']

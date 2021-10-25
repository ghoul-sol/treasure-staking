import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, read, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const newOwner = deployer;
    const magicArbitrum = "0x86083653fef09AB89BEC7dA3815dD76AF9bCc006";
    await deploy('TreasuryMine', {
      from: deployer,
      log: true,
      args: [magicArbitrum, (await deployments.get('TreasuryStake')).address, newOwner]
    })

    // const secondaryOwner = "0x3577a25A1cf6b5B254798101aAb6B23A3beD8b28";
    // if ((await read('TreasuryMine', 'owner')) != secondaryOwner) {
    //   await execute(
    //     'TreasuryMine',
    //     { from: deployer, log: true },
    //     'transferOwnership',
    //     secondaryOwner
    //   );
    // }

    const toExclude = [
      "0x07EdbD02923435Fe2C141F390510178C79DBbc46",
      "0x16E95f6Bf27f0b16B19AD7D07635E69c49897272",
      "0x3577a25A1cf6b5B254798101aAb6B23A3beD8b28"
    ];

    const excludedAddresses = await read('TreasuryMine', 'getExcludedAddresses');

    for (let i = 0; i < toExclude.length; i++) {
      if(excludedAddresses.indexOf(toExclude[i]) == -1) {
        await execute(
          'TreasuryMine',
          { from: deployer, log: true },
          'addExcludedAddress',
          toExclude[i]
        );
      }
    }
};
export default func;
func.tags = ['treasuryMine'];
func.dependencies = ['treasuryStake']

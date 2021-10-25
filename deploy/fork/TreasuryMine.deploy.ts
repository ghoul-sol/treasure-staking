import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

import ERC20 from '@openzeppelin/contracts/build/contracts/ERC20.json';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { ethers, deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    async function transferErc20(erc20Address: any, signer: any, to: any, amount: any) {
      signer = await ethers.provider.getSigner(signer);
      const erc20 = new ethers.Contract(erc20Address, ERC20.abi, signer);
      await erc20.transfer(to, amount);
    }

    async function impersonateTransferFrom(
      erc20Address: string,
      from: string,
      to: string,
      amount: any
    ) {
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [from]}
      )

      if (erc20Address == "0xe") {
        const signer = await ethers.provider.getSigner(from);
        const tx = await signer.sendTransaction({
          to: to,
          value: amount
        });
        await tx.wait()
      } else {
        await transferErc20(erc20Address, from, to, amount);
      }

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [from]}
      )
    }

    const magicSource = "0xA82fCEFd303Fa68864b787a5f118b09cE5A4c93d";
    const magicArbitrum = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
    const treasuresArbitrum = "0xEBba467eCB6b21239178033189CeAE27CA12EaDf";
    const newOwner = "0x3D210e741cDeDeA81efCd9711Ce7ef7FEe45684B";

    // pk: 3b2dd7cb3312b608c47d6d940cf77716ff5474d10bd993c03df6ff554d2020f6
    const testerWallet = "0x4A8ab0d4234340D1E956709A64466Cf0D115b145";

    // fund with eth
    await impersonateTransferFrom(
      "0xe",
      deployer,
      testerWallet,
      ethers.utils.parseUnits('1', 'ether'),
    )

    // fund with magic token
    await impersonateTransferFrom(
      magicArbitrum,
      magicSource,
      testerWallet,
      ethers.utils.parseUnits('20', 'ether'),
    )

    const TreasuryMine = await deployments.get('TreasuryMine');
    await impersonateTransferFrom(
      magicArbitrum,
      magicSource,
      TreasuryMine.address,
      ethers.utils.parseUnits('20', 'ether'),
    )

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [newOwner]}
    )

    // start the mine
    const treasuryMine = new ethers.Contract(
      TreasuryMine.address,
      TreasuryMine.abi,
      await ethers.provider.getSigner(newOwner)
    );

    await treasuryMine.init();

    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [newOwner]}
    )

};
export default func;
func.tags = ['treasuryMine'];
func.dependencies = ['treasuryStake']

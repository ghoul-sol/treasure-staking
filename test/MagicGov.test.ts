import hre from 'hardhat';
import {expect} from 'chai';
import {getBlockTime, mineBlock, getCurrentTime} from './utils';

const {ethers, deployments, getNamedAccounts, artifacts} = hre;
const { deploy } = deployments;

describe.only('MagicGov', function () {
  const sushiLP = "0xB7E50106A5bd3Cf21AF210A755F9C8740890A8c9";
  const lpRewards = "0x73EB8b2b235F7957f830ea66ABE433D9EED9f0E3";
  const testWallet = "0xa82fcefd303fa68864b787a5f118b09ce5a4c93d";
  const testWallet2 = "0x85905b40a61fdBAdBb4372Bb3EF4e9da60Ebc98D";
  const TreasuryMineArbitrum = "0xDf19f1216aA406DF8bC585246bee7D96933f285F";

  let treasuryMine: any, treasuryStake: any;
  let magicToken: any, lpToken: any, magicGov: any;
  let staker1: any, staker2: any, staker3: any, hacker: any, deployer: any;
  let staker1Signer: any, staker2Signer: any, staker3Signer: any, hackerSigner: any, deployerSigner: any;
  let checkDeposit: any;
  let checkPendingRewardsPosition: any;
  let checkIndexes: any;

  before(async function () {
    const namedAccounts = await getNamedAccounts();
    staker1 = namedAccounts.staker1;
    staker2 = namedAccounts.staker2;
    staker3 = namedAccounts.staker3;
    hacker = namedAccounts.hacker;
    deployer = namedAccounts.deployer;

    staker1Signer = await ethers.provider.getSigner(staker1);
    staker2Signer = await ethers.provider.getSigner(staker2);
    staker3Signer = await ethers.provider.getSigner(staker3);
    hackerSigner = await ethers.provider.getSigner(hacker);
    deployerSigner = await ethers.provider.getSigner(deployer);
  });

  beforeEach(async function () {
    await deployments.fixture();

    lpToken = new ethers.Contract(
      sushiLP,
      (await artifacts.readArtifact('ERC20Mintable')).abi,
      await ethers.provider.getSigner(deployer)
    );

    treasuryMine = new ethers.Contract(
      TreasuryMineArbitrum,
      (await deployments.get('TreasuryMine')).abi,
      await ethers.provider.getSigner(deployer)
    );

    magicToken = new ethers.Contract(
      await treasuryMine.magic(),
      (await artifacts.readArtifact('ERC20Mintable')).abi,
      await ethers.provider.getSigner(deployer)
    );

    const MagicGov = await ethers.getContractFactory('MagicGov')
    magicGov = await MagicGov.deploy(TreasuryMineArbitrum, sushiLP, lpRewards);
    await magicGov.deployed();
  });

  it('init()', async function () {
    expect(await magicGov.treasuryMine()).to.be.equal(TreasuryMineArbitrum);
    expect(await magicGov.sushiLP()).to.be.equal(sushiLP);
    expect(await magicGov.lpRewards()).to.be.equal(lpRewards);
  });

  it('totalSupply()', async function () {
    expect(await magicGov.totalSupply()).to.be.equal(await magicToken.totalSupply());
  });

  it('getMineBalance()', async function () {
    expect(await magicGov.getMineBalance(testWallet)).to.be.equal('180196229813499272392755');
    expect(await magicGov.getMineBalance(testWallet2)).to.be.equal('198134502090878928892509');
  });

  it('getLPBalance()', async function () {
    expect(await magicGov.getLPBalance(testWallet)).to.be.equal('43865572860027005115');
    expect(await magicGov.getLPBalance(testWallet2)).to.be.equal('24213755632936178359852');
  });

  it('balanceOf()', async function () {
    expect(await magicGov.balanceOf(testWallet)).to.be.equal('180240095386359299397870');
    expect(await magicGov.balanceOf(testWallet2)).to.be.equal('222348257723815107252361');
  });
});

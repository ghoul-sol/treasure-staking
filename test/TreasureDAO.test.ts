import hre from 'hardhat';
import {expect} from 'chai';
import {getBlockTime, mineBlock, getCurrentTime} from './utils';

const {ethers, deployments, getNamedAccounts, artifacts} = hre;
const { deploy } = deployments;

describe('TreasureDAO', function () {
  const sushiLP = "0xB7E50106A5bd3Cf21AF210A755F9C8740890A8c9";
  const lpRewards = "0x73EB8b2b235F7957f830ea66ABE433D9EED9f0E3";
  const testWallet = "0xa82fcefd303fa68864b787a5f118b09ce5a4c93d";
  const testWallet2 = "0x85905b40a61fdBAdBb4372Bb3EF4e9da60Ebc98D";
  const testWallet3 = "0x2b5321c1AfDDFb6680aAFFf4Df96A209e18dEa1c";
  const testWallet4 = "0x7c3410819f4Dd207358e48ADB7a8006d58fa828E";

  const TreasuryMineArbitrum = "0xDf19f1216aA406DF8bC585246bee7D96933f285F";

  let treasuryMine: any, treasuryStake: any;
  let magicToken: any, lpToken: any, treasureDAO: any;
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

    const TreasureDAO = await ethers.getContractFactory('TreasureDAO')
    treasureDAO = await TreasureDAO.deploy(TreasuryMineArbitrum, sushiLP, lpRewards);
    await treasureDAO.deployed();
  });

  it('init()', async function () {
    expect(await treasureDAO.treasuryMine()).to.be.equal(TreasuryMineArbitrum);
    expect(await treasureDAO.sushiLP()).to.be.equal(sushiLP);
    expect(await treasureDAO.lpRewards()).to.be.equal(lpRewards);
  });

  it('totalSupply()', async function () {
    expect(await treasureDAO.totalSupply()).to.be.equal(await magicToken.totalSupply());
  });

  it('getMineBalance()', async function () {
    expect(await treasureDAO.getMineBalance(testWallet)).to.be.equal('180196229813499272392755');
    expect(await treasureDAO.getMineBalance(testWallet2)).to.be.equal('198134502090878928892509');
    expect(await treasureDAO.getMineBalance(testWallet3)).to.be.equal('2411248209237196763986129');
    expect(await treasureDAO.getMineBalance(testWallet4)).to.be.equal('11020797828861264508998');
  });

  it('getLPBalance()', async function () {
    expect(await treasureDAO.getLPBalance(testWallet)).to.be.equal('43865572860027005115');
    expect(await treasureDAO.getLPBalance(testWallet2)).to.be.equal('24213755632936178359852');
    expect(await treasureDAO.getLPBalance(testWallet3)).to.be.equal('17546229144010843988345');
    expect(await treasureDAO.getLPBalance(testWallet4)).to.be.equal('1625012547464634236710');
  });

  it('balanceOf()', async function () {
    expect(await treasureDAO.balanceOf(testWallet)).to.be.equal('180240095386359299397870');
    expect(await treasureDAO.balanceOf(testWallet2)).to.be.equal('222348257723815107252361');
    expect(await treasureDAO.balanceOf(testWallet3)).to.be.equal('2428794438381207607974474');
    expect(await treasureDAO.balanceOf(testWallet4)).to.be.equal('12645810376325898745708');
  });
});

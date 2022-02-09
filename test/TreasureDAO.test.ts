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

  const AtlasMineArbitrum = "0xA0A89db1C899c49F98E6326b764BAFcf167fC2CE";

  let atlasMine: any, treasuryStake: any;
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

    atlasMine = new ethers.Contract(
      AtlasMineArbitrum,
      (await deployments.get('AtlasMine')).abi,
      await ethers.provider.getSigner(deployer)
    );

    magicToken = new ethers.Contract(
      await atlasMine.magic(),
      (await artifacts.readArtifact('ERC20Mintable')).abi,
      await ethers.provider.getSigner(deployer)
    );

    const TreasureDAO = await ethers.getContractFactory('TreasureDAO')
    treasureDAO = await TreasureDAO.deploy(AtlasMineArbitrum, sushiLP, lpRewards);
    await treasureDAO.deployed();
  });

  it('init()', async function () {
    expect(await treasureDAO.atlasMine()).to.be.equal(AtlasMineArbitrum);
    expect(await treasureDAO.sushiLP()).to.be.equal(sushiLP);
    expect(await treasureDAO.lpRewards()).to.be.equal(lpRewards);
  });

  it('totalSupply()', async function () {
    expect(await treasureDAO.totalSupply()).to.be.equal(await magicToken.totalSupply());
  });

  it('getMineBalance()', async function () {
    expect(await treasureDAO.getMineBalance(testWallet)).to.be.equal('381464174845282622983837');
    expect(await treasureDAO.getMineBalance(testWallet2)).to.be.equal('0');
    expect(await treasureDAO.getMineBalance(testWallet3)).to.be.equal('5000000000000000000000000');
    expect(await treasureDAO.getMineBalance(testWallet4)).to.be.equal('38006117332477996155295');
  });

  it('getLPBalance()', async function () {
    expect(await treasureDAO.getLPBalance(testWallet)).to.be.equal('0');
    expect(await treasureDAO.getLPBalance(testWallet2)).to.be.equal('0');
    expect(await treasureDAO.getLPBalance(testWallet3)).to.be.equal('0');
    expect(await treasureDAO.getLPBalance(testWallet4)).to.be.equal('0');
  });

  it('balanceOf()', async function () {
    expect(await treasureDAO.balanceOf(testWallet)).to.be.equal('381464174845282622983837');
    expect(await treasureDAO.balanceOf(testWallet2)).to.be.equal('0');
    expect(await treasureDAO.balanceOf(testWallet3)).to.be.equal('5000000000000000000000000');
    expect(await treasureDAO.balanceOf(testWallet4)).to.be.equal('38006117332477996155295');
  });
});

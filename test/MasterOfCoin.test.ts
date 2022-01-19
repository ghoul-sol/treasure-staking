import hre from 'hardhat';
import {expect} from 'chai';
import {getBlockTime, mineBlock, getCurrentTime, setNextBlockTime} from './utils';

const {ethers, deployments, getNamedAccounts} = hre;
const { deploy } = deployments;

describe('MasterOfCoin', function () {
  let masterOfCoin: any, treasuryStake: any;
  let magicToken: any, lpToken: any;
  let stream1: any, stream2: any, stream3: any, hacker: any, deployer: any;
  let stream1Signer: any, stream2Signer: any, stream3Signer: any, hackerSigner: any, deployerSigner: any;
  let checkDeposit: any;
  let checkPendingRewardsPosition: any;
  let checkIndexes: any;

  before(async function () {
    const namedAccounts = await getNamedAccounts();
    stream1 = namedAccounts.staker1;
    stream2 = namedAccounts.staker2;
    stream3 = namedAccounts.staker3;
    hacker = namedAccounts.hacker;
    deployer = namedAccounts.deployer;

    stream1Signer = await ethers.provider.getSigner(stream1);
    stream2Signer = await ethers.provider.getSigner(stream2);
    stream3Signer = await ethers.provider.getSigner(stream3);
    hackerSigner = await ethers.provider.getSigner(hacker);
    deployerSigner = await ethers.provider.getSigner(deployer);
  });

  describe("use proxy", function () {
    beforeEach(async function () {
      await deployments.fixture(['MasterOfCoin'], { fallbackToGlobal: true });

      const ERC20Mintable = await ethers.getContractFactory('ERC20Mintable')
      magicToken = await ERC20Mintable.deploy()
      await magicToken.deployed();

      const MasterOfCoin = await deployments.get('MasterOfCoin');
      masterOfCoin = new ethers.Contract(MasterOfCoin.address, MasterOfCoin.abi, deployerSigner);
      await masterOfCoin.setMagicToken(magicToken.address);

      // const MasterOfCoin = await ethers.getContractFactory('MasterOfCoin')
      // masterOfCoin = await MasterOfCoin.deploy()
      // await masterOfCoin.deployed();
      // await masterOfCoin.init(magicToken.address);
    });

    it('init()', async function () {
      await expect(masterOfCoin.init(magicToken.address)).to.be.revertedWith("Initializable: contract is already initialized");
    });

    it('magic()', async function () {
      expect(await masterOfCoin.magic()).to.be.equal(magicToken.address);
    });

    it('MASTER_OF_COIN_ADMIN_ROLE()', async function () {
      expect(await masterOfCoin.MASTER_OF_COIN_ADMIN_ROLE()).to.be.equal("0x275f12656528ceae7cba2736a15cb4ce098fc404b67e9825ec13a82aaf8fabec");
    });

    it('hasRole()', async function () {
      const MASTER_OF_COIN_ADMIN_ROLE = await masterOfCoin.MASTER_OF_COIN_ADMIN_ROLE();
      expect(await masterOfCoin.hasRole(MASTER_OF_COIN_ADMIN_ROLE, deployer)).to.be.true;
    });

    it('grantRole()', async function () {
      const MASTER_OF_COIN_ADMIN_ROLE = await masterOfCoin.MASTER_OF_COIN_ADMIN_ROLE();

      expect(await masterOfCoin.hasRole(MASTER_OF_COIN_ADMIN_ROLE, hacker)).to.be.false;

      await masterOfCoin.grantRole(MASTER_OF_COIN_ADMIN_ROLE, hacker)

      expect(await masterOfCoin.hasRole(MASTER_OF_COIN_ADMIN_ROLE, hacker)).to.be.true;
    });

    it('addStream()', async function () {
      const totalRewards = ethers.utils.parseEther("1");
      const startTimestamp = await getCurrentTime();
      const timeDelta = 2000;
      const endTimestamp = startTimestamp + timeDelta;

      await masterOfCoin.addStream(stream1, totalRewards, startTimestamp, endTimestamp);

      expect(await masterOfCoin.getStreams()).to.be.deep.equal([stream1]);
      const ratePerSecond = await masterOfCoin.getRatePerSecond(stream1)
      expect(ratePerSecond).to.be.equal(totalRewards.div(timeDelta));
      expect(await masterOfCoin.getGlobalRatePerSecond()).to.be.equal(ratePerSecond);

      const currentTime = await getCurrentTime();
      expect(await masterOfCoin.getPendingRewards(stream1)).to.be.equal(ratePerSecond.mul(currentTime - startTimestamp));
    });

    describe('with streams', function () {
      let streamsDetails: any[];
      let timestamps: any[];

      beforeEach(async function () {
        let currentTime = await getCurrentTime() + 5000;
        streamsDetails = [
          {
            address: stream1,
            signer: stream1Signer,
            totalRewards: ethers.utils.parseEther("1"),
            startTimestamp: currentTime,
            endTimestamp: currentTime + 2000
          },
          {
            address: stream2,
            signer: stream2Signer,
            totalRewards: ethers.utils.parseEther("25"),
            startTimestamp: currentTime + 100,
            endTimestamp: currentTime + 1100
          },
          {
            address: stream3,
            signer: stream3Signer,
            totalRewards: ethers.utils.parseEther("5000"),
            startTimestamp: currentTime + 200,
            endTimestamp: currentTime + 4200
          }
        ]

        timestamps = [
          currentTime + 100, // 1 active
          currentTime + 105, // 1 & 2 active
          currentTime + 400, // 1 & 2 & 3 active
          currentTime + 1101, // 1 & 3 active
          currentTime + 2001, // 3 active
          currentTime + 4201, // 0 active
        ]

        for (let index = 0; index < streamsDetails.length; index++) {
          const _stream = streamsDetails[index];
          await masterOfCoin.addStream(_stream.address, _stream.totalRewards, _stream.startTimestamp, _stream.endTimestamp);
          await magicToken.mint(masterOfCoin.address, _stream.totalRewards);
        }
      });

      it('getStreams()', async function () {
        expect(await masterOfCoin.getStreams()).to.be.deep.equal([stream1, stream2, stream3]);
      });

      it('addStream()', async function () {
        const totalRewards = ethers.utils.parseEther("1");
        const startTimestamp = await getCurrentTime();
        const timeDelta = 2000;
        const endTimestamp = startTimestamp + timeDelta;

        await expect(
          masterOfCoin.addStream(stream2, totalRewards, startTimestamp, endTimestamp)
        ).to.be.revertedWith("Stream for address already exists");
      });

      it('getRatePerSecond()', async function () {
        await mineBlock(streamsDetails[0].startTimestamp + 300);

        for (let index = 0; index < streamsDetails.length; index++) {
          const _stream = streamsDetails[index];
          const ratePerSecond = await masterOfCoin.getRatePerSecond(_stream.address);
          expect(ratePerSecond).to.be.equal(_stream.totalRewards.div(_stream.endTimestamp - _stream.startTimestamp));
        }
      });

      it('getGlobalRatePerSecond()', async function () {
        await mineBlock(streamsDetails[0].startTimestamp + 300);
        let globalRatePerSecond = ethers.BigNumber.from(0);

        for (let index = 0; index < streamsDetails.length; index++) {
          const _stream = streamsDetails[index];
          const ratePerSecond = await masterOfCoin.getRatePerSecond(_stream.address);
          globalRatePerSecond = globalRatePerSecond.add(ratePerSecond);
        }
        expect(await masterOfCoin.getGlobalRatePerSecond()).to.be.equal(globalRatePerSecond);
      });

      it('getPendingRewards()', async function () {
        for (let i = 0; i < timestamps.length; i++) {
          await mineBlock(timestamps[i]);

          for (let index = 0; index < streamsDetails.length; index++) {
            const _stream = streamsDetails[index];
            let currentTime = await getCurrentTime();
            const ratePerSecond = await masterOfCoin.getRatePerSecond(_stream.address);
            if (_stream.startTimestamp < currentTime && currentTime < _stream.endTimestamp) {
              expect(ratePerSecond).to.be.equal(_stream.totalRewards.div(_stream.endTimestamp - _stream.startTimestamp));
            } else {
              expect(ratePerSecond).to.be.equal(0);
            }
          }
        }
      });

      it('grantTokenToStream()', async function () {
        const _stream = streamsDetails[1];
        const grant = ethers.utils.parseEther("5.5");

        await setNextBlockTime(_stream.startTimestamp + 300);
        await masterOfCoin.connect(_stream.signer).requestRewards();

        const streamConfigBefore = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceBefore = await magicToken.balanceOf(masterOfCoin.address);

        await magicToken.mint(deployer, grant);
        await magicToken.approve(masterOfCoin.address, grant);
        await setNextBlockTime(_stream.startTimestamp + 500);
        await masterOfCoin.grantTokenToStream(_stream.address, grant);

        const streamConfigAfter = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceAfter = await magicToken.balanceOf(masterOfCoin.address);

        expect(streamConfigAfter.startTimestamp).to.be.equal(streamConfigBefore.startTimestamp);
        expect(streamConfigAfter.endTimestamp).to.be.equal(streamConfigBefore.endTimestamp);
        expect(streamConfigAfter.lastRewardTimestamp).to.be.equal(streamConfigBefore.lastRewardTimestamp);
        expect(streamConfigAfter.paid).to.be.equal(streamConfigBefore.paid);

        expect(streamConfigAfter.totalRewards).to.be.equal(streamConfigBefore.totalRewards.add(grant));
        expect(masterOfCoinBalanceAfter).to.be.equal(masterOfCoinBalanceBefore.add(grant));

        expect(streamConfigAfter.ratePerSecond).to.be.equal(ethers.utils.parseEther("0.032857142857142857"));
      });

      it('fundStream()', async function () {
        const _stream = streamsDetails[1];
        const grant = ethers.utils.parseEther("5.5");

        await setNextBlockTime(_stream.startTimestamp + 300);
        await masterOfCoin.connect(_stream.signer).requestRewards();

        const streamConfigBefore = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceBefore = await magicToken.balanceOf(masterOfCoin.address);

        await setNextBlockTime(_stream.startTimestamp + 500);
        await masterOfCoin.fundStream(_stream.address, grant);

        const streamConfigAfter = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceAfter = await magicToken.balanceOf(masterOfCoin.address);

        expect(streamConfigAfter.startTimestamp).to.be.equal(streamConfigBefore.startTimestamp);
        expect(streamConfigAfter.endTimestamp).to.be.equal(streamConfigBefore.endTimestamp);
        expect(streamConfigAfter.lastRewardTimestamp).to.be.equal(streamConfigBefore.lastRewardTimestamp);
        expect(streamConfigAfter.paid).to.be.equal(streamConfigBefore.paid);

        expect(streamConfigAfter.totalRewards).to.be.equal(streamConfigBefore.totalRewards.add(grant));
        expect(masterOfCoinBalanceAfter).to.be.equal(masterOfCoinBalanceBefore);

        expect(streamConfigAfter.ratePerSecond).to.be.equal(ethers.utils.parseEther("0.032857142857142857"));
      });

      it('defundStream()', async function () {
        const _stream = streamsDetails[2];
        const defund = ethers.utils.parseEther("1250");

        await setNextBlockTime(_stream.startTimestamp + 800);
        await masterOfCoin.connect(_stream.signer).requestRewards();

        const streamConfigBefore = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceBefore = await magicToken.balanceOf(masterOfCoin.address);

        await setNextBlockTime(_stream.startTimestamp + 1200);
        await masterOfCoin.defundStream(_stream.address, defund);

        const streamConfigAfter = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceAfter = await magicToken.balanceOf(masterOfCoin.address);

        expect(streamConfigAfter.startTimestamp).to.be.equal(streamConfigBefore.startTimestamp);
        expect(streamConfigAfter.endTimestamp).to.be.equal(streamConfigBefore.endTimestamp);
        expect(streamConfigAfter.lastRewardTimestamp).to.be.equal(streamConfigBefore.lastRewardTimestamp);
        expect(streamConfigAfter.paid).to.be.equal(streamConfigBefore.paid);

        expect(streamConfigAfter.totalRewards).to.be.equal(streamConfigBefore.totalRewards.sub(defund));
        expect(masterOfCoinBalanceAfter).to.be.equal(masterOfCoinBalanceBefore);

        expect(streamConfigAfter.ratePerSecond).to.be.equal(ethers.utils.parseEther("0.859375"));
      });

      it('updateStreamTime()', async function () {
        const newTimestamps = [
          {
            startTimestamp: streamsDetails[2].startTimestamp + 750,
            endTimestamp: streamsDetails[2].endTimestamp + 750,
          },
          {
            startTimestamp: 0,
            endTimestamp: streamsDetails[2].endTimestamp + 750 + 2000,
          },
          {
            startTimestamp: streamsDetails[2].startTimestamp + 1500 + 250,
            endTimestamp: 0,
          },
        ]

        const newStreamData = [
          {
            ...streamsDetails[2],
            startTimestamp: streamsDetails[2].startTimestamp + 750,
            endTimestamp: streamsDetails[2].endTimestamp + 750,
            lastRewardTimestamp: streamsDetails[2].startTimestamp + 750,
            ratePerSecond: ethers.utils.parseEther("1.09375"),
            getRatePerSecond: 0,
            getPendingRewards: 0,
            paid: ethers.utils.parseEther("625"),
          },
          {
            ...streamsDetails[2],
            startTimestamp: streamsDetails[2].startTimestamp + 750,
            endTimestamp: streamsDetails[2].endTimestamp + 750 + 2000,
            lastRewardTimestamp: streamsDetails[2].startTimestamp + 1000,
            ratePerSecond: ethers.utils.parseEther("0.713315217391304347"),
            getRatePerSecond: ethers.utils.parseEther("0.713315217391304347"),
            getPendingRewards: ethers.utils.parseEther("7.133152173913043470"),
            paid: ethers.utils.parseEther("898.4375"),
          },
          {
            ...streamsDetails[2],
            startTimestamp: streamsDetails[2].startTimestamp + 1500 + 250,
            endTimestamp: streamsDetails[2].endTimestamp + 750 + 2000,
            lastRewardTimestamp: streamsDetails[2].startTimestamp + 1500 + 250,
            ratePerSecond: ethers.utils.parseEther("0.748980978260869565"),
            getRatePerSecond: 0,
            getPendingRewards: 0,
            paid: ethers.utils.parseEther("1255.095108695652173500"),
          },
        ]

        const _stream = streamsDetails[2];

        let futureTimestamp = _stream.startTimestamp + 500;

        for (let index = 0; index < newTimestamps.length; index++) {
          await setNextBlockTime(futureTimestamp);
          await masterOfCoin.connect(_stream.signer).requestRewards();
          futureTimestamp += 500;

          await masterOfCoin.updateStreamTime(
            _stream.address,
            newTimestamps[index].startTimestamp,
            newTimestamps[index].endTimestamp
          );

          await mineBlock(futureTimestamp - 500 + 10);

          const streamConfig = await masterOfCoin.getStreamConfig(_stream.address);
          const getRatePerSecond = await masterOfCoin.getRatePerSecond(_stream.address);
          const getPendingRewards = await masterOfCoin.getPendingRewards(_stream.address);

          expect(streamConfig.totalRewards).to.be.equal(_stream.totalRewards);

          expect(streamConfig.startTimestamp).to.be.equal(newStreamData[index].startTimestamp);
          expect(streamConfig.endTimestamp).to.be.equal(newStreamData[index].endTimestamp);

          expect(streamConfig.lastRewardTimestamp).to.be.equal(newStreamData[index].lastRewardTimestamp);
          expect(streamConfig.ratePerSecond).to.be.equal(newStreamData[index].ratePerSecond);
          expect(getRatePerSecond).to.be.equal(newStreamData[index].getRatePerSecond);
          expect(getPendingRewards).to.be.equal(newStreamData[index].getPendingRewards);
          expect(streamConfig.paid).to.be.equal(newStreamData[index].paid);
        }

        await mineBlock(futureTimestamp);

        const streamConfigAfter = await masterOfCoin.getStreamConfig(_stream.address);
        const getRatePerSecondAfter = await masterOfCoin.getRatePerSecond(_stream.address);
        const getPendingRewardsAfter = await masterOfCoin.getPendingRewards(_stream.address);

        expect(streamConfigAfter.ratePerSecond).to.be.equal(newStreamData[2].ratePerSecond);
        expect(getRatePerSecondAfter).to.be.equal(newStreamData[2].ratePerSecond);
        expect(getPendingRewardsAfter).to.be.equal(newStreamData[2].ratePerSecond.mul(250));
      });

      it('removeStream()', async function () {
        const _stream = streamsDetails[2];
        const defund = ethers.utils.parseEther("1250");

        await setNextBlockTime(_stream.startTimestamp + 800);
        await masterOfCoin.connect(_stream.signer).requestRewards();

        const streamConfigBefore = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceBefore = await magicToken.balanceOf(masterOfCoin.address);
        const streamBalanceBefore = await magicToken.balanceOf(_stream.address);

        await setNextBlockTime(_stream.startTimestamp + 1200);
        await masterOfCoin.removeStream(_stream.address);
        await masterOfCoin.connect(_stream.signer).requestRewards();

        const streamConfigAfter = await masterOfCoin.getStreamConfig(_stream.address);
        const masterOfCoinBalanceAfter = await magicToken.balanceOf(masterOfCoin.address);
        const streamBalanceAfter = await magicToken.balanceOf(_stream.address);

        expect(streamConfigAfter.startTimestamp).to.be.equal(0);
        expect(streamConfigAfter.endTimestamp).to.be.equal(0);
        expect(streamConfigAfter.lastRewardTimestamp).to.be.equal(0);
        expect(streamConfigAfter.paid).to.be.equal(0);
        expect(streamConfigAfter.totalRewards).to.be.equal(0);
        expect(streamConfigAfter.ratePerSecond).to.be.equal(0);

        expect(masterOfCoinBalanceAfter).to.be.equal(masterOfCoinBalanceBefore);
        expect(streamBalanceBefore.totalRewards).to.be.equal(streamBalanceAfter.totalRewards);
      });

      it('withdrawMagic()', async function () {
        const amount = ethers.utils.parseEther("500");

        const masterOfCoinBalanceBefore = await magicToken.balanceOf(masterOfCoin.address);
        const deployerBalanceBefore = await magicToken.balanceOf(deployer);

        await masterOfCoin.withdrawMagic(deployer, amount);

        const masterOfCoinBalanceAfter = await magicToken.balanceOf(masterOfCoin.address);
        const deployerBalanceAfter = await magicToken.balanceOf(deployer);

        expect(masterOfCoinBalanceAfter).to.be.equal(masterOfCoinBalanceBefore.sub(amount))
        expect(deployerBalanceAfter).to.be.equal(deployerBalanceBefore.add(amount))
      });
    })
  })

  describe('requestRewards()', function () {
    let scenarios: any[] = Array.from({ length: 7 });
    let scenarioTimestamps: any[];
    let magicTokenFresh: any;
    let masterOfCoinFresh: any;

    before(async function () {
      let currentTime = await getCurrentTime() + 5000;

      let scenarioStreams = [
        {
          address: stream1,
          signer: stream1Signer,
          totalRewards: ethers.utils.parseEther("1"),
          startTimestamp: currentTime,
          endTimestamp: currentTime + 2000
        },
        {
          address: stream2,
          signer: stream2Signer,
          totalRewards: ethers.utils.parseEther("25"),
          startTimestamp: currentTime + 100,
          endTimestamp: currentTime + 1100
        },
        {
          address: stream3,
          signer: stream3Signer,
          totalRewards: ethers.utils.parseEther("5000"),
          startTimestamp: currentTime + 200,
          endTimestamp: currentTime + 4200
        }
      ]

      scenarioTimestamps = [
        currentTime + 100, // 1 active
        currentTime + 120, // 1 & 2 active
        currentTime + 400, // 1 & 2 & 3 active
        currentTime + 1101, // 1 & 3 active
        currentTime + 2001, // 3 active
        currentTime + 4201, // 0 active
      ]

      scenarios = [
        // + 0, 0 active
        [
          {
            ...scenarioStreams[0],
            lastRewardTimestamp: scenarioStreams[0].startTimestamp,
            ratePerSecond: ethers.utils.parseEther("0.0005"),
            paid: 0,
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioStreams[1].startTimestamp,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: 0,
          },
          {
            ...scenarioStreams[2],
            lastRewardTimestamp: scenarioStreams[2].startTimestamp,
            ratePerSecond: ethers.utils.parseEther("1.25"),
            paid: 0,
          }
        ],
        // + 100, 1 & 2 active
        [
          {
            ...scenarioStreams[0],
            lastRewardTimestamp: scenarioTimestamps[0],
            ratePerSecond: ethers.utils.parseEther("0.0005"),
            paid: ethers.utils.parseEther("0.05"),
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioStreams[1].startTimestamp + 5,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: ethers.utils.parseEther("0.125"),
          },
          {
            ...scenarioStreams[2],
            lastRewardTimestamp: scenarioStreams[2].startTimestamp,
            ratePerSecond: ethers.utils.parseEther("1.25"),
            paid: 0,
          }
        ],
        // + 120, 1 & 2 active
        [
          {
            ...scenarioStreams[0],
            lastRewardTimestamp: scenarioTimestamps[1],
            ratePerSecond: ethers.utils.parseEther("0.0005"),
            paid: ethers.utils.parseEther("0.06"),
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioTimestamps[1] + 5,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: ethers.utils.parseEther("0.625"),
          },
          {
            ...scenarioStreams[2],
            lastRewardTimestamp: scenarioStreams[2].startTimestamp,
            ratePerSecond: ethers.utils.parseEther("1.25"),
            paid: 0,
          }
        ],
        // + 400, 1 & 2 & 3 active
        [
          {
            ...scenarioStreams[0],
            lastRewardTimestamp: scenarioTimestamps[2],
            ratePerSecond: ethers.utils.parseEther("0.0005"),
            paid: ethers.utils.parseEther("0.2"),
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioTimestamps[2] + 5,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: ethers.utils.parseEther("7.625"),
          },
          {
            ...scenarioStreams[2],
            lastRewardTimestamp: scenarioTimestamps[2] + 10,
            ratePerSecond: ethers.utils.parseEther("1.25"),
            paid: ethers.utils.parseEther("262.5"),
          }
        ],
        // + 1101, 1 & 3 active
        [
          {
            ...scenarioStreams[0],
            totalRewards: scenarioStreams[0].totalRewards.mul(2),
            lastRewardTimestamp: scenarioTimestamps[3],
            ratePerSecond: ethers.utils.parseEther("0.001125"),
            paid: ethers.utils.parseEther("0.988625"),
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioTimestamps[3] + 5,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: ethers.utils.parseEther("25"),
          },
          {
            ...scenarioStreams[2],
            lastRewardTimestamp: scenarioTimestamps[3] + 10,
            ratePerSecond: ethers.utils.parseEther("1.25"),
            paid: ethers.utils.parseEther("1138.75"),
          }
        ],
        // + 2001, 3 active
        [
          {
            ...scenarioStreams[0],
            totalRewards: scenarioStreams[0].totalRewards.mul(2).sub(ethers.utils.parseEther("0.5")),
            lastRewardTimestamp: scenarioTimestamps[4],
            ratePerSecond: ethers.utils.parseEther("0.000568826473859844"),
            paid: scenarioStreams[0].totalRewards.mul(2).sub(ethers.utils.parseEther("0.5")),
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioTimestamps[3] + 5,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: scenarioStreams[1].totalRewards,
          },
          {
            ...scenarioStreams[2],
            lastRewardTimestamp: scenarioTimestamps[4] + 10,
            ratePerSecond: ethers.utils.parseEther("1.25"),
            paid: ethers.utils.parseEther("2263.75"),
          }
        ],
        // + 4201, 0 active
        [
          {
            ...scenarioStreams[0],
            totalRewards: scenarioStreams[0].totalRewards.mul(2).sub(ethers.utils.parseEther("0.5")),
            lastRewardTimestamp: scenarioTimestamps[4],
            ratePerSecond: ethers.utils.parseEther("0.000568826473859844"),
            paid: scenarioStreams[0].totalRewards.mul(2).sub(ethers.utils.parseEther("0.5")),
          },
          {
            ...scenarioStreams[1],
            lastRewardTimestamp: scenarioTimestamps[3] + 5,
            ratePerSecond: ethers.utils.parseEther("0.025"),
            paid: scenarioStreams[1].totalRewards,
          },
          {
            ...scenarioStreams[2],
            endTimestamp: scenarioStreams[2].endTimestamp + 1000,
            lastRewardTimestamp: scenarioTimestamps[5] + 10,
            ratePerSecond: ethers.utils.parseEther("0.858027594857322044"),
            paid: ethers.utils.parseEther("4151.410708686108496800"),
          }
        ]
      ]

      const ERC20Mintable = await ethers.getContractFactory('ERC20Mintable')
      magicTokenFresh = await ERC20Mintable.deploy()
      await magicTokenFresh.deployed();

      const MasterOfCoinFresh = await ethers.getContractFactory('MasterOfCoin')
      masterOfCoinFresh = await MasterOfCoinFresh.deploy()
      await masterOfCoinFresh.deployed();
      await masterOfCoinFresh.init(magicTokenFresh.address);

      for (let index = 0; index < scenarioStreams.length; index++) {
        const _stream = scenarioStreams[index];
        await masterOfCoinFresh.addStream(_stream.address, _stream.totalRewards, _stream.startTimestamp, _stream.endTimestamp);
        await magicTokenFresh.mint(masterOfCoinFresh.address, _stream.totalRewards);
      }
    })

    scenarios.forEach((testCase, i) => {
      it(`[${i}] requestRewards()`, async function () {
        let scenario = scenarios[i];

        for (let index = 0; index < scenario.length; index++) {
          const _stream = scenario[index];
          const streamConfig = await masterOfCoinFresh.getStreamConfig(_stream.address);
          let steamBalance = await magicTokenFresh.balanceOf(_stream.address);

          expect(streamConfig.totalRewards).to.be.equal(_stream.totalRewards);
          expect(streamConfig.startTimestamp).to.be.equal(_stream.startTimestamp);
          expect(streamConfig.endTimestamp).to.be.equal(_stream.endTimestamp);
          expect(streamConfig.ratePerSecond).to.be.equal(_stream.ratePerSecond);

          expect(streamConfig.lastRewardTimestamp).to.be.equal(_stream.lastRewardTimestamp);
          expect(streamConfig.paid).to.be.equal(_stream.paid);
          expect(steamBalance).to.be.equal(_stream.paid);

          if (i == 3 && index == 0) {
            // test grantTokenToStream()
            await magicTokenFresh.mint(deployer, _stream.totalRewards);
            await magicTokenFresh.approve(masterOfCoinFresh.address, _stream.totalRewards);
            await masterOfCoinFresh.grantTokenToStream(_stream.address, _stream.totalRewards);
          }

          if (i == 4 && index == 0) {
            // test defundStream()
            await masterOfCoinFresh.defundStream(_stream.address, ethers.utils.parseEther("0.5"))
          }

          if (i == 5 && index == 2) {
            // test updateStreamTime()
            await masterOfCoinFresh.updateStreamTime(_stream.address, 0, _stream.endTimestamp + 1000)
          }

          if (i < 6) {
            let futureTimestamp = scenarioTimestamps[i] + 5 * index;
            await setNextBlockTime(futureTimestamp);
            let tx = await masterOfCoinFresh.connect(_stream.signer).requestRewards();
            expect(await getBlockTime(tx.blockNumber)).to.be.equal(futureTimestamp)
          }
        }
      })
    })
  })
});

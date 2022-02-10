import hre from 'hardhat';
import {expect} from 'chai';
import {getBlockTime, mineBlock, getCurrentTime, setNextBlockTime} from './utils';
import { deployMockContract } from 'ethereum-waffle';

const {ethers, deployments, getNamedAccounts, artifacts} = hre;
const { deploy } = deployments;

describe.only('AtlasMine', function () {
  let atlasMine: any, masterOfCoin: any, mockILegionMetadataStore: any;
  let magicToken: any, treasure: any, legion: any;
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
    await deployments.fixture(['AtlasMine'], { fallbackToGlobal: true });

    const ERC20Mintable = await ethers.getContractFactory('ERC20Mintable')
    magicToken = await ERC20Mintable.deploy()
    await magicToken.deployed();

    const MasterOfCoin = await deployments.get('MasterOfCoin');
    masterOfCoin = new ethers.Contract(MasterOfCoin.address, MasterOfCoin.abi, deployerSigner);
    await masterOfCoin.setMagicToken(magicToken.address);

    const ERC1155Mintable = await ethers.getContractFactory('ERC1155Mintable')
    treasure = await ERC1155Mintable.deploy()
    await treasure.deployed();

    const ERC721Mintable = await ethers.getContractFactory('ERC721Mintable')
    legion = await ERC721Mintable.deploy()
    await legion.deployed();

    mockILegionMetadataStore = await deployMockContract(deployerSigner, (await artifacts.readArtifact('ILegionMetadataStore')).abi);

    const AtlasMine = await deployments.get('AtlasMine');
    atlasMine = new ethers.Contract(AtlasMine.address, AtlasMine.abi, deployerSigner);
    await atlasMine.setMagicToken(magicToken.address);
    await atlasMine.setTreasure(treasure.address);
    await atlasMine.setLegion(legion.address);
    await atlasMine.setLegionMetadataStore(mockILegionMetadataStore.address);
  });

  it('init()', async function () {
    await expect(atlasMine.init(magicToken.address, masterOfCoin.address)).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it('getLockBoost()', async function () {
    expect((await atlasMine.getLockBoost(0)).boost).to.be.equal(ethers.utils.parseEther('0.1'));
    expect((await atlasMine.getLockBoost(1)).boost).to.be.equal(ethers.utils.parseEther('0.25'));
    expect((await atlasMine.getLockBoost(2)).boost).to.be.equal(ethers.utils.parseEther('0.8'));
    expect((await atlasMine.getLockBoost(3)).boost).to.be.equal(ethers.utils.parseEther('1.8'));
    expect((await atlasMine.getLockBoost(4)).boost).to.be.equal(ethers.utils.parseEther('4'));
  });

  it('setMagicToken()', async function () {
    expect(await atlasMine.magic()).to.be.equal(magicToken.address);
    await atlasMine.setMagicToken(deployer);
    expect(await atlasMine.magic()).to.be.equal(deployer);
  });

  it('setTreasure()', async function () {
    expect(await atlasMine.treasure()).to.be.equal(treasure.address);
    await atlasMine.setTreasure(deployer);
    expect(await atlasMine.treasure()).to.be.equal(deployer);
  });

  it('setLegion()', async function () {
    expect(await atlasMine.legion()).to.be.equal(legion.address);
    await atlasMine.setLegion(deployer);
    expect(await atlasMine.legion()).to.be.equal(deployer);
  });

  it('setLegionMetadataStore()', async function () {
    expect(await atlasMine.legionMetadataStore()).to.be.equal(mockILegionMetadataStore.address);
    await atlasMine.setLegionMetadataStore(deployer);
    expect(await atlasMine.legionMetadataStore()).to.be.equal(deployer);
  });

  it('setLegionBoostMatrix()', async function () {
    let legionBoostMatrix = [
      // GENESIS
      // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
      [
        ethers.utils.parseEther('6'),
        ethers.utils.parseEther('2'),
        ethers.utils.parseEther('0.75'),
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('0.5'),
        ethers.utils.parseEther('0')
      ],
      // AUXILIARY
      // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
      [
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0.25'),
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0.1'),
        ethers.utils.parseEther('0.05'),
        ethers.utils.parseEther('0')
      ],
      // RECRUIT
      // LEGENDARY,RARE,SPECIAL,UNCOMMON,COMMON,RECRUIT
      [
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0')
      ],
    ];

    expect(await atlasMine.getLegionBoostMatrix()).to.be.deep.equal(legionBoostMatrix);

    for (let i = 0; i < legionBoostMatrix.length; i++) {
      for (let j = 0; j < legionBoostMatrix[i].length; j++) {
        const boost = legionBoostMatrix[i][j];
        expect(await atlasMine.getLegionBoost(i, j)).to.be.deep.equal(boost);
      }
    }

    legionBoostMatrix[2][0] = legionBoostMatrix[1][0];
    legionBoostMatrix[2][1] = legionBoostMatrix[1][1];
    legionBoostMatrix[2][2] = legionBoostMatrix[1][2];
    legionBoostMatrix[2][3] = legionBoostMatrix[1][3];
    legionBoostMatrix[2][4] = legionBoostMatrix[1][4];
    legionBoostMatrix[2][5] = legionBoostMatrix[1][5];

    await expect(atlasMine.connect(hackerSigner).setLegionBoostMatrix(legionBoostMatrix)).to.be.reverted;
    await atlasMine.setLegionBoostMatrix(legionBoostMatrix);

    expect(await atlasMine.getLegionBoostMatrix()).to.be.deep.equal(legionBoostMatrix);

    for (let i = 0; i < legionBoostMatrix.length; i++) {
      for (let j = 0; j < legionBoostMatrix[i].length; j++) {
        const boost = legionBoostMatrix[i][j];
        expect(await atlasMine.getLegionBoost(i, j)).to.be.deep.equal(boost);
      }
    }

    expect(await atlasMine.getLegionBoost(3, 1)).to.be.deep.equal(0);
    expect(await atlasMine.getLegionBoost(1, 6)).to.be.deep.equal(0);
    expect(await atlasMine.getLegionBoost(3, 6)).to.be.deep.equal(0);
  });

  it('isLegion1_1()', async function () {
    const tokenId = 55;
    let metadata = {
        legionGeneration: 0,
        legionClass: 0,
        legionRarity: 0,
        questLevel: 0,
        craftLevel: 0,
        constellationRanks: [0,1,2,3,4,5]
    };
    await mockILegionMetadataStore.mock.metadataForLegion.withArgs(tokenId).returns(metadata);
    expect(await atlasMine.isLegion1_1(tokenId)).to.be.true;

    for (let index = 1; index < 6; index++) {
      metadata.legionRarity = index;
      await mockILegionMetadataStore.mock.metadataForLegion.withArgs(index).returns(metadata);
      expect(await atlasMine.isLegion1_1(index)).to.be.false;
    }
  })

  describe('with multiple deposits', function () {
    let depositsScenarios: any[];
    let withdrawAllScenarios: any[];
    let harvestScenarios: any[];
    let rewards: any[];

    let startTimestamp: any;

    beforeEach(async function () {
      startTimestamp = await getCurrentTime();

      depositsScenarios = [
        {
          address: staker1,
          signer: staker1Signer,
          timestamp: startTimestamp + 500,
          depositId: 1,
          amount: ethers.utils.parseEther('50'),
          lpAmount: ethers.utils.parseEther('55'),
          lock: 0
        },
        {
          address: staker1,
          signer: staker1Signer,
          timestamp: startTimestamp + 1000,
          depositId: 2,
          amount: ethers.utils.parseEther('10'),
          lpAmount: ethers.utils.parseEther('12.5'),
          lock: 1
        },
        {
          address: staker1,
          signer: staker1Signer,
          timestamp: startTimestamp + 1500,
          depositId: 3,
          amount: ethers.utils.parseEther('20'),
          lpAmount: ethers.utils.parseEther('56'),
          lock: 3
        },
        {
          address: staker2,
          signer: staker2Signer,
          timestamp: startTimestamp + 2000,
          depositId: 1,
          amount: ethers.utils.parseEther('20'),
          lpAmount: ethers.utils.parseEther('100'),
          lock: 4
        },
      ]

      withdrawAllScenarios = [
        {
          address: staker1,
          signer: staker1Signer,
          timestamp: startTimestamp + 1500,
          lock: 3,
          prevBal: ethers.utils.parseEther('60'),
          balanceOf: ethers.utils.parseEther('80'),
        },
        {
          address: staker2,
          signer: staker2Signer,
          timestamp: startTimestamp + 2000,
          lock: 4,
          prevBal: ethers.utils.parseEther('0'),
          balanceOf: ethers.utils.parseEther('20')
        }
      ]

      // 0.18/s	    deposit 1	         deposit 2	        deposit 3	         deposit 4
      // 0-500	    90                 0	                0	                 0
      // 500-1000	  90	               0	                0	                 0
      // 1000-1500	73.33333333333331	 16.666666666666668	0	                 0
      // 1500-2000	40.08097165991902	 9.109311740890687	40.80971659919028	 0
      // 2000-5000	132.88590604026845 30.201342281879192	135.3020134228188	 241.61073825503354
    	//            426.3002110335208	 55.977320689436546	176.11173002200906 241.61073825503354

      harvestScenarios = [
        ethers.utils.parseEther('426.435915731507395120'),
        ethers.utils.parseEther('55.967253575342589800'),
        ethers.utils.parseEther('176.066629350868135656'),
        ethers.utils.parseEther('241.530201342281879100'),
      ]

      rewards = [
        {
          address: depositsScenarios[0].address,
          signer: depositsScenarios[0].signer,
          deposit: depositsScenarios[0].amount.add(depositsScenarios[1].amount).add(depositsScenarios[2].amount),
          reward: harvestScenarios[0].add(harvestScenarios[1]).add(harvestScenarios[2])
        },
        {
          address: depositsScenarios[3].address,
          signer: depositsScenarios[3].signer,
          deposit: depositsScenarios[3].amount,
          reward: harvestScenarios[3]
        }
      ]

      const totalRewards = ethers.utils.parseEther("900");
      const timeDelta = 5000;
      const endTimestamp = startTimestamp + timeDelta;

      await masterOfCoin.addStream(atlasMine.address, totalRewards, startTimestamp, endTimestamp, false);
      await magicToken.mint(masterOfCoin.address, totalRewards)
      await atlasMine.setUtilizationOverride(ethers.utils.parseEther("1"));

      for (let index = 0; index < depositsScenarios.length; index++) {
        const deposit = depositsScenarios[index];
        await magicToken.mint(deposit.address, deposit.amount);
        await setNextBlockTime(deposit.timestamp);
        await magicToken.connect(deposit.signer).approve(atlasMine.address, deposit.amount);
        await atlasMine.connect(deposit.signer).deposit(deposit.amount, deposit.lock);
      }
    })

    it('deposit()', async function () {
      let totalLpToken = ethers.utils.parseEther("0");
      let magicTotalDeposits = ethers.utils.parseEther("0");

      for (let index = 0; index < depositsScenarios.length; index++) {
        const deposit = depositsScenarios[index];
        const userInfo = await atlasMine.userInfo(deposit.address, deposit.depositId);

        expect(userInfo.originalDepositAmount).to.be.equal(deposit.amount);
        expect(userInfo.depositAmount).to.be.equal(deposit.amount);
        expect(userInfo.lpAmount).to.be.equal(deposit.lpAmount);
        expect(userInfo.lock).to.be.equal(deposit.lock);

        totalLpToken = totalLpToken.add(userInfo.lpAmount);
        magicTotalDeposits = magicTotalDeposits.add(deposit.amount)
      }

      expect(await atlasMine.magicTotalDeposits()).to.be.equal(magicTotalDeposits);
      expect(await atlasMine.totalLpToken()).to.be.equal(totalLpToken);
    });

    it('magicTotalDeposits()', async function () {
      let magicTotalDeposits = ethers.utils.parseEther('0');
      for (let index = 0; index < depositsScenarios.length; index++) {
        magicTotalDeposits = magicTotalDeposits.add(depositsScenarios[index].amount)
      }
      expect(await atlasMine.magicTotalDeposits()).to.be.equal(magicTotalDeposits);
    })

    describe('utilization', function () {
      let totalSupply: any;
      let rewards: any;
      let circulatingSupply: any;
      let ONE: any;
      let utilizationOverride: any[];

      beforeEach(async function () {
        // set to default
        await atlasMine.setUtilizationOverride(ethers.utils.parseEther("0"));

        utilizationOverride = [
          [ethers.utils.parseEther("0"), ethers.utils.parseEther("0")],
          [ethers.utils.parseEther("0.1"), ethers.utils.parseEther("0")],
          [ethers.utils.parseEther("0.3"), ethers.utils.parseEther("0.5")],
          [ethers.utils.parseEther("0.4"), ethers.utils.parseEther("0.6")],
          [ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.8")],
          [ethers.utils.parseEther("0.6"), ethers.utils.parseEther("1")],
        ]

        totalSupply = await magicToken.totalSupply();
        const magicTotalDeposits = await atlasMine.magicTotalDeposits();
        const bal = await magicToken.balanceOf(atlasMine.address);
        rewards = bal.sub(magicTotalDeposits);
        circulatingSupply = totalSupply.sub(rewards);
        ONE = await atlasMine.ONE();
      })

      it('getExcludedAddresses() && utilization() && addExcludedAddress() && removeExcludedAddress()', async function () {
        const util = await atlasMine.utilization();
        const magicTotalDeposits = await atlasMine.magicTotalDeposits();
        expect(magicTotalDeposits.mul(ONE).div(circulatingSupply)).to.be.equal(util);

        await magicToken.mint(deployer, totalSupply);
        const newUtil = await atlasMine.utilization();
        expect(newUtil).to.be.equal(ethers.utils.parseEther("0.060988997584835695"));

        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([]);
        await atlasMine.addExcludedAddress(deployer);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([deployer]);
        expect(await atlasMine.utilization()).to.be.equal(ethers.utils.parseEther("0.156425979226629958"));

        await atlasMine.addExcludedAddress(staker1);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker1]);

        await atlasMine.addExcludedAddress(staker2);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker1, staker2]);

        await atlasMine.addExcludedAddress(staker3);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker1, staker2, staker3]);

        await atlasMine.removeExcludedAddress(staker1);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker3, staker2]);

        await atlasMine.removeExcludedAddress(deployer);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([staker2, staker3]);

        await atlasMine.removeExcludedAddress(staker3);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([staker2]);

        await expect(atlasMine.removeExcludedAddress(staker3)).to.be.revertedWith("Address is not excluded");

        await atlasMine.removeExcludedAddress(staker2);
        expect(await atlasMine.getExcludedAddresses()).to.be.deep.equal([]);

        await expect(atlasMine.removeExcludedAddress(staker2)).to.be.revertedWith("Address is not excluded");

        const newUtil2 = await atlasMine.utilization();
        expect(newUtil2).to.be.equal(ethers.utils.parseEther("0.061049315637171707"));
        await atlasMine.addExcludedAddress(deployer);
        expect(await atlasMine.utilization()).to.be.equal(ethers.utils.parseEther("0.156779129562272670"));
      });

      it('setUtilizationOverride()', async function () {
        for (let index = 0; index < utilizationOverride.length; index++) {
          const utilization = utilizationOverride[index][0];
          await atlasMine.setUtilizationOverride(utilization);

          let expectedUtil: any;
          if (utilization == 0) {
            expectedUtil = await atlasMine.utilization();
          } else {
            expectedUtil = utilization;
          }

          expect(await atlasMine.utilization()).to.be.equal(expectedUtil);
        }
      });

      it('getRealMagicReward()', async function () {
        const rewardsAmount = ethers.utils.parseEther("1");

        for (let index = 0; index < utilizationOverride.length; index++) {
          const utilization = utilizationOverride[index][0];
          const effectiveness = utilizationOverride[index][1];

          if (utilization > 0) {
            await atlasMine.setUtilizationOverride(utilization);
            const result = await atlasMine.getRealMagicReward(rewardsAmount);
            expect(result.distributedRewards).to.be.equal(rewardsAmount.mul(effectiveness).div(ONE))
            expect(result.undistributedRewards).to.be.equal(rewardsAmount.sub(result.distributedRewards))
          }
        }
      });
    })

    it('withdrawPosition()', async function () {
      for (let index = 0; index < depositsScenarios.length; index++) {
        const deposit = depositsScenarios[index];

        await expect(atlasMine.connect(deposit.signer).withdrawPosition(deposit.depositId, deposit.amount))
          .to.be.revertedWith("Position is still locked");

        // time travel to beginning of vesting
        const timelock = (await atlasMine.getLockBoost(deposit.lock)).timelock;
        await setNextBlockTime(deposit.timestamp + timelock.toNumber() + 1);

        const balBefore = await magicToken.balanceOf(deposit.address);
        let balAfter: any;

        if (deposit.lock != 0) {
          await atlasMine.connect(deposit.signer).withdrawPosition(deposit.depositId, deposit.amount)
          balAfter = await magicToken.balanceOf(deposit.address);
          expect(balAfter.sub(balBefore)).to.be.equal(0);

          expect(await atlasMine.connect(deposit.signer).calcualteVestedPrincipal(deposit.address, deposit.depositId))
            .to.be.equal(0);

          const vestingTime = (await atlasMine.getVestingTime(deposit.lock)).toNumber();
          const vestHalf = deposit.timestamp + timelock.toNumber() + vestingTime / 2 + 1;
          const vestingEnd = deposit.timestamp + timelock.toNumber() + vestingTime + 1;

          await mineBlock(vestHalf);

          let principalVested = await atlasMine.connect(deposit.signer).calcualteVestedPrincipal(deposit.address, deposit.depositId);
          expect(principalVested).to.be.equal(deposit.amount.div(2));

          await mineBlock(vestingEnd);
          principalVested = await atlasMine.connect(deposit.signer).calcualteVestedPrincipal(deposit.address, deposit.depositId);
          expect(principalVested).to.be.equal(deposit.amount);

          await atlasMine.connect(deposit.signer).withdrawPosition(deposit.depositId, deposit.amount);

          balAfter = await magicToken.balanceOf(deposit.address);
          expect(balAfter.sub(balBefore)).to.be.equal(deposit.amount);
        } else {
          await atlasMine.connect(deposit.signer).withdrawPosition(deposit.depositId, deposit.amount);
          const balAfter = await magicToken.balanceOf(deposit.address);

          expect(balAfter.sub(balBefore)).to.be.equal(deposit.amount);
        }
      }
    });

    it('withdrawAll()', async function () {
      for (let index = 0; index < withdrawAllScenarios.length; index++) {
        const staker = withdrawAllScenarios[index];

        // time travel to beginning of vesting
        const timelock = (await atlasMine.getLockBoost(staker.lock)).timelock;
        await setNextBlockTime(staker.timestamp + timelock.toNumber() + 1);

        let balAfter: any;

        await atlasMine.connect(staker.signer).withdrawAll();

        balAfter = await magicToken.balanceOf(staker.address);
        expect(balAfter).to.be.equal(staker.prevBal);

        const vestingTime = (await atlasMine.getVestingTime(staker.lock)).toNumber();
        const vestingEnd = staker.timestamp + timelock.toNumber() + vestingTime + 1;

        await mineBlock(vestingEnd);

        await atlasMine.connect(staker.signer).withdrawAll();

        balAfter = await magicToken.balanceOf(staker.address);
        expect(balAfter).to.be.equal(staker.balanceOf);
      }
    });

    it('harvestPosition()', async function () {
      await mineBlock(startTimestamp + 6000);

      for (let index = 0; index < harvestScenarios.length; index++) {
        const deposit = depositsScenarios[index];
        const reward = harvestScenarios[index];

        const pendingRewardsPosition = await atlasMine.pendingRewardsPosition(deposit.address, deposit.depositId);
        expect(pendingRewardsPosition).to.be.equal(reward);

        const balBefore = await magicToken.balanceOf(deposit.address);
        await atlasMine.connect(deposit.signer).harvestPosition(deposit.depositId)
        const balAfter = await magicToken.balanceOf(deposit.address);
        expect(balAfter.sub(balBefore)).to.be.equal(reward);
      }
    });

    it('harvestAll()', async function () {
      for (let index = 0; index < depositsScenarios.length; index++) {
        expect(await magicToken.balanceOf(depositsScenarios[index].address)).to.be.equal(0);
      }

      let firstTimestamp = startTimestamp + 2000;
      const timestamps = [
        firstTimestamp + 50,
        firstTimestamp + 188,
        firstTimestamp + 378,
        firstTimestamp + 657,
        firstTimestamp + 938,
        firstTimestamp + 1749,
        firstTimestamp + 1837,
        firstTimestamp + 2333,
      ]

      for (let index = 0; index < timestamps.length; index++) {
        await mineBlock(timestamps[index]);

        for (let i = 0; i < depositsScenarios.length; i++) {
          await setNextBlockTime(timestamps[index] + (i + 1) * 9);
          const deposit = depositsScenarios[i];
          await atlasMine.connect(deposit.signer).harvestPosition(deposit.depositId);
        }
      }

      await mineBlock(startTimestamp + 6000);

      const rewards = [
        {
          address: depositsScenarios[0].address,
          signer: depositsScenarios[0].signer,
          reward: harvestScenarios[0].add(harvestScenarios[1]).add(harvestScenarios[2])
        },
        {
          address: depositsScenarios[3].address,
          signer: depositsScenarios[3].signer,
          reward: harvestScenarios[3]
        }
      ]

      for (let index = 0; index < rewards.length; index++) {
        await atlasMine.connect(rewards[index].signer).harvestAll();
        const balAfter = await magicToken.balanceOf(rewards[index].address);
        expect(balAfter).to.be.closeTo(rewards[index].reward, 10000);
      }
    });

    it('withdrawAndHarvestPosition()', async function () {
      for (let index = 0; index < depositsScenarios.length; index++) {
        const deposit = depositsScenarios[index];
        const reward = harvestScenarios[index];

        // time travel to beginning of vesting
        const timelock = (await atlasMine.getLockBoost(deposit.lock)).timelock;
        const vestingTime = (await atlasMine.getVestingTime(deposit.lock)).toNumber();
        const vestingEnd = deposit.timestamp + timelock.toNumber() + vestingTime + 1;

        await mineBlock(vestingEnd);

        const balBefore = await magicToken.balanceOf(deposit.address);
        await atlasMine.connect(deposit.signer).withdrawAndHarvestPosition(deposit.depositId, deposit.amount);
        const balAfter = await magicToken.balanceOf(deposit.address);
        expect(balAfter.sub(balBefore)).to.be.equal(deposit.amount.add(reward));
      }
    });

    it('withdrawAndHarvestAll()', async function () {
      for (let index = 0; index < depositsScenarios.length; index++) {
        expect(await magicToken.balanceOf(depositsScenarios[index].address)).to.be.equal(0);
      }

      let firstTimestamp = startTimestamp + 2000;
      const timestamps = [
        firstTimestamp + 50,
        firstTimestamp + 188,
        firstTimestamp + 378,
        firstTimestamp + 657,
        firstTimestamp + 938,
        firstTimestamp + 1749,
        firstTimestamp + 1837,
        firstTimestamp + 2333,
      ]

      for (let index = 0; index < timestamps.length; index++) {
        await mineBlock(timestamps[index]);

        for (let i = 0; i < depositsScenarios.length; i++) {
          await setNextBlockTime(timestamps[index] + (i + 1) * 9);
          const deposit = depositsScenarios[i];
          await atlasMine.connect(deposit.signer).harvestPosition(deposit.depositId);
        }
      }

      await mineBlock(startTimestamp + 6000);

      const deposit = depositsScenarios[3];

      // time travel to beginning of vesting
      const timelock = (await atlasMine.getLockBoost(deposit.lock)).timelock;
      const vestingTime = (await atlasMine.getVestingTime(deposit.lock)).toNumber();
      const vestingEnd = deposit.timestamp + timelock.toNumber() + vestingTime + 1;

      await mineBlock(vestingEnd);

      for (let index = 0; index < rewards.length; index++) {
        const reward = rewards[index];
        await atlasMine.connect(reward.signer).withdrawAndHarvestAll();
        const balAfter = await magicToken.balanceOf(reward.address);
        expect(balAfter).to.be.closeTo(reward.reward.add(reward.deposit), 10000);
      }
    });

    it('toggleUnlockAll()', async function () {
      await expect(atlasMine.connect(hackerSigner).toggleUnlockAll()).to.be.reverted;

      for (let index = 0; index < withdrawAllScenarios.length; index++) {
        const staker = withdrawAllScenarios[index];

        await expect(atlasMine.connect(staker.signer).withdrawAll()).to.be.revertedWith("Position is still locked");
        await atlasMine.toggleUnlockAll();
        await atlasMine.connect(staker.signer).withdrawAll();
        await atlasMine.toggleUnlockAll();

        let balAfter = await magicToken.balanceOf(staker.address);
        expect(balAfter).to.be.equal(staker.balanceOf);
      }
    });

    it('withdrawUndistributedRewards()', async function () {
      await atlasMine.setUtilizationOverride(ethers.utils.parseEther("0.4"));

      const deposit = depositsScenarios[3];
      const timelock = (await atlasMine.getLockBoost(deposit.lock)).timelock;
      const vestingTime = (await atlasMine.getVestingTime(deposit.lock)).toNumber();
      const vestingEnd = deposit.timestamp + timelock.toNumber() + vestingTime + 1;

      await mineBlock(vestingEnd);

      await atlasMine.setUtilizationOverride(ethers.utils.parseEther("1"));

      expect(await magicToken.balanceOf(deployer)).to.be.equal(0);
      const totalUndistributedRewards = await atlasMine.totalUndistributedRewards();
      expect(totalUndistributedRewards).to.be.equal(ethers.utils.parseEther("215.856"));

      await atlasMine.withdrawUndistributedRewards(deployer);

      expect(await magicToken.balanceOf(deployer)).to.be.equal(totalUndistributedRewards);
      expect(await atlasMine.totalUndistributedRewards()).to.be.equal(0);
    });

    it('calcualteVestedPrincipal()');

    describe('NFT staking', function () {
      let boostScenarios: any[];
      let metadata: any;

      beforeEach(async function () {
        boostScenarios = [
          {
            nft: treasure.address,
            tokenId: 96,
            amount: 10,
            metadata: {
              legionGeneration: 0,
              legionRarity: 0,
            },
            boost: ethers.utils.parseEther("0.008")
          },
          {
            nft: treasure.address,
            tokenId: 105,
            amount: 5,
            metadata: {
              legionGeneration: 0,
              legionRarity: 0,
            },
            boost: ethers.utils.parseEther("0.067")
          },
          {
            nft: treasure.address,
            tokenId: 47,
            amount: 5,
            metadata: {
              legionGeneration: 0,
              legionRarity: 0,
            },
            boost: ethers.utils.parseEther("0.073")
          },
          {
            nft: legion.address,
            tokenId: 98,
            amount: 1,
            metadata: {
              legionGeneration: 0,
              legionRarity: 0,
            },
            boost: ethers.utils.parseEther("6")
          },
          {
            nft: legion.address,
            tokenId: 77,
            amount: 1,
            metadata: {
              legionGeneration: 0,
              legionRarity: 1,
            },
            boost: ethers.utils.parseEther("2")
          },
          {
            nft: legion.address,
            tokenId: 44,
            amount: 1,
            metadata: {
              legionGeneration: 0,
              legionRarity: 2,
            },
            boost: ethers.utils.parseEther("0.75")
          },
          {
            nft: legion.address,
            tokenId: 33,
            amount: 1,
            metadata: {
              legionGeneration: 1,
              legionRarity: 2,
            },
            boost: ethers.utils.parseEther("0")
          },
          {
            nft: legion.address,
            tokenId: 22,
            amount: 1,
            metadata: {
              legionGeneration: 1,
              legionRarity: 1,
            },
            boost: ethers.utils.parseEther("0.25")
          },
        ]

        metadata = {
            legionGeneration: 1,
            legionClass: 0,
            legionRarity: 0,
            questLevel: 0,
            craftLevel: 0,
            constellationRanks: [0,1,2,3,4,5]
        };

        for (let index = 0; index < boostScenarios.length; index++) {
          const scenario = boostScenarios[index];
          if (scenario.nft == legion.address) {
            metadata.legionGeneration = scenario.metadata.legionGeneration;
            metadata.legionRarity = scenario.metadata.legionRarity;
            await mockILegionMetadataStore.mock.metadataForLegion.withArgs(scenario.tokenId).returns(metadata);
          }
        }
      })

      it('getNftBoost()', async function () {
        for (let index = 0; index < boostScenarios.length; index++) {
          const scenario = boostScenarios[index];
          expect(await atlasMine.getNftBoost(scenario.nft, scenario.tokenId, scenario.amount))
            .to.be.equal(scenario.boost.mul(scenario.amount));
        }
      });

      describe('stakeTreasure()', function () {
        it('Cannot stake Treasure', async function () {
          await atlasMine.setTreasure(ethers.constants.AddressZero);
          await expect(atlasMine.stakeTreasure(1, 1)).to.be.revertedWith("Cannot stake Treasure");
        });

        it('Amount is 0', async function () {
          await expect(atlasMine.stakeTreasure(1, 0)).to.be.revertedWith("Amount is 0");
        });

        it('Max 20 treasures per wallet', async function () {
          for (let index = 0; index < 5; index++) {
            await treasure.functions['mint(address,uint256,uint256)'](staker1, index, 5);
            await treasure.connect(staker1Signer).setApprovalForAll(atlasMine.address, true);

            if (index == 4) {
              await expect(atlasMine.connect(staker1Signer).stakeTreasure(index, 5))
                .to.be.revertedWith("Max 20 treasures per wallet");
            } else {
              await atlasMine.connect(staker1Signer).stakeTreasure(index, 5);
            }
          }
        });

        it('stake boosts', async function () {
          let totalBoost = ethers.utils.parseEther("0");

          for (let index = 0; index < boostScenarios.length; index++) {
            const scenario = boostScenarios[index];

            if (scenario.nft == treasure.address) {
              const boostBefore = await atlasMine.boosts(staker1);

              await treasure.functions['mint(address,uint256,uint256)'](staker1, scenario.tokenId, scenario.amount);
              await treasure.connect(staker1Signer).setApprovalForAll(atlasMine.address, true);
              await expect(atlasMine.connect(staker1Signer).stakeTreasure(scenario.tokenId, scenario.amount))
                .to.emit(atlasMine, "Staked").withArgs(treasure.address, scenario.tokenId, scenario.amount, boostBefore.add(scenario.boost.mul(scenario.amount)))

              expect(await treasure.balanceOf(atlasMine.address, scenario.tokenId)).to.be.equal(scenario.amount);
              const boostAfter = await atlasMine.boosts(staker1);
              const boostDiff = boostAfter.sub(boostBefore);
              expect(boostDiff).to.be.equal(scenario.boost.mul(scenario.amount));
              totalBoost = totalBoost.add(boostDiff);
            }
          }

          expect(await atlasMine.boosts(staker1)).to.be.equal(totalBoost);
        })
      })

      describe('stakeLegion()', function () {
        it('Cannot stake Legion', async function () {
          await atlasMine.setLegion(ethers.constants.AddressZero);
          await expect(atlasMine.stakeLegion(1)).to.be.revertedWith("Cannot stake Legion");
        });

        it('NFT already staked', async function () {
          await legion.mint(staker1)
          await legion.connect(staker1Signer).approve(atlasMine.address, 0);
          await atlasMine.connect(staker1Signer).stakeLegion(0);
          await expect(atlasMine.connect(staker1Signer).stakeLegion(0)).to.be.revertedWith("NFT already staked");
        });

        it('Max 3 legions per wallet', async function () {
          let metadata = {
              legionGeneration: 1,
              legionClass: 0,
              legionRarity: 0,
              questLevel: 0,
              craftLevel: 0,
              constellationRanks: [0,1,2,3,4,5]
          };

          for (let index = 0; index < 4; index++) {
            await mockILegionMetadataStore.mock.metadataForLegion.withArgs(index).returns(metadata);
            await legion.mint(deployer)
            await legion.approve(atlasMine.address, index);

            if (index == 3) {
              await expect(atlasMine.stakeLegion(index)).to.be.revertedWith("Max 3 legions per wallet");
            } else {
              await atlasMine.stakeLegion(index);
            }
          }
        });

        it('Max 1 1/1 legion per wallet', async function () {
          let metadata = {
              legionGeneration: 0,
              legionClass: 0,
              legionRarity: 0,
              questLevel: 0,
              craftLevel: 0,
              constellationRanks: [0,1,2,3,4,5]
          };
          await mockILegionMetadataStore.mock.metadataForLegion.withArgs(0).returns(metadata);
          await legion.mint(staker1)
          await legion.connect(staker1Signer).approve(atlasMine.address, 0);
          await atlasMine.connect(staker1Signer).stakeLegion(0);

          await mockILegionMetadataStore.mock.metadataForLegion.withArgs(1).returns(metadata);
          await legion.mint(staker1)
          await legion.connect(staker1Signer).approve(atlasMine.address, 1);
          await expect(atlasMine.connect(staker1Signer).stakeLegion(1)).to.be.revertedWith("Max 1 1/1 legion per wallet");
        });

        it('stake boosts', async function () {
          let totalBoost = ethers.utils.parseEther("0");

          for (let index = 0; index < boostScenarios.length; index++) {
            const scenario = boostScenarios[index];

            const stakedLegions = await atlasMine.getStakedLegions(staker1);

            if (scenario.nft == legion.address && stakedLegions.length < 3) {
              const boostBefore = await atlasMine.boosts(staker1);
              await legion.mintWithId(staker1, scenario.tokenId);
              await legion.connect(staker1Signer).approve(atlasMine.address, scenario.tokenId);
              await atlasMine.connect(staker1Signer).stakeLegion(scenario.tokenId);
              expect(await legion.ownerOf(scenario.tokenId)).to.be.equal(atlasMine.address);
              const boostAfter = await atlasMine.boosts(staker1);
              expect(boostAfter.sub(boostBefore)).to.be.equal(scenario.boost);
              totalBoost = totalBoost.add(scenario.boost);
            }
          }

          expect(await atlasMine.boosts(staker1)).to.be.equal(totalBoost);
        })
      })

      it('harvest scenarios with staking', async function () {
        for (let index = 0; index < depositsScenarios.length; index++) {
          expect(await magicToken.balanceOf(depositsScenarios[index].address)).to.be.equal(0);
        }

        const steps = [
          {
            timestamp: startTimestamp + 2500,
            stake: [
              {
                address: staker1,
                signer: staker1Signer,
                depositId: 1,
                index: 7
              },
              {
                address: staker1,
                signer: staker1Signer,
                depositId: 3,
                index: 5
              },
              {
                address: staker2,
                signer: staker2Signer,
                depositId: 1,
                index: 3
              },
            ],
            unstake: [],
          },
          {
            timestamp: startTimestamp + 3000,
            stake: [
              {
                address: staker1,
                signer: staker1Signer,
                depositId: 1,
                index: 2
              },
              {
                address: staker1,
                signer: staker1Signer,
                depositId: 2,
                index: 4
              },
            ],
            unstake: [],
          },
          {
            timestamp: startTimestamp + 3500,
            stake: [],
            unstake: [
              {
                address: staker1,
                signer: staker1Signer,
                depositId: 1,
                index: 2
              },
            ]
          },
          {
            timestamp: startTimestamp + 4000,
            stake: [],
            unstake: [
              {
                address: staker2,
                signer: staker2Signer,
                depositId: 1,
                index: 3
              },
            ]
          },
        ]

        for (let index = 0; index < steps.length; index++) {
          const step = steps[index];

          await mineBlock(step.timestamp);

          for (let i = 0; i < step.stake.length; i++) {
            const stake = step.stake[i];
            const tokenId = boostScenarios[stake.index].tokenId;
            const amount = boostScenarios[stake.index].amount;

            if (boostScenarios[stake.index].nft == legion.address) {
              await legion.mintWithId(stake.address, tokenId);
              await legion.connect(stake.signer).approve(atlasMine.address, tokenId);
              await atlasMine.connect(stake.signer).stakeLegion(tokenId);
            } else {
              await treasure.functions['mint(address,uint256,uint256)'](stake.address, tokenId, amount);
              await treasure.connect(stake.signer).setApprovalForAll(atlasMine.address, true);
              await atlasMine.connect(stake.signer).stakeTreasure(tokenId, amount);
            }
          }

          for (let i = 0; i < step.unstake.length; i++) {
            const unstake = step.unstake[i];
            const tokenId = boostScenarios[unstake.index].tokenId;
            const amount = boostScenarios[unstake.index].amount;

            if (boostScenarios[unstake.index].nft == legion.address) {
              await atlasMine.connect(unstake.signer).unstakeLegion(tokenId);
            } else {
              await atlasMine.connect(unstake.signer).unstakeTreasure(tokenId, amount);
            }
          }

          await atlasMine.connect(staker1Signer).harvestAll();
          await atlasMine.connect(staker2Signer).harvestAll();
        }

        await mineBlock(startTimestamp + 6000);

        const rewards = [
          {
            address: depositsScenarios[0].address,
            signer: depositsScenarios[0].signer,
            reward: ethers.utils.parseEther('707.994049297877092636')
          },
          {
            address: depositsScenarios[3].address,
            signer: depositsScenarios[3].signer,
            reward: ethers.utils.parseEther('192.005950702122902940')
          }
        ]

        for (let index = 0; index < rewards.length; index++) {
          await atlasMine.connect(rewards[index].signer).harvestAll();
          const balAfter = await magicToken.balanceOf(rewards[index].address);
          expect(balAfter).to.be.closeTo(rewards[index].reward, 10000);
        }
      })

      describe('limit of deposits', function () {
        it('makes deposits and stakes NFT', async function () {
          const makeDeposits = async (count: any) => {
            for (let index = 0; index < count; index++) {
              const deposit = depositsScenarios[0];
              await magicToken.mint(deposit.address, deposit.amount);
              await magicToken.connect(deposit.signer).approve(atlasMine.address, deposit.amount);
              await atlasMine.connect(deposit.signer).deposit(deposit.amount, deposit.lock);
            }
          }

          const deposit = depositsScenarios[0];
          const tokenId = 1;
          const tokenAmount = 1;

          // Deposits: 3, GasLimit: 227321
          // Deposits: 10, GasLimit: 241688
          // Deposits: 50, GasLimit: 624958
          // Deposits: 100, GasLimit: 1107476
          // Deposits: 200, GasLimit: 2064629
          // Deposits: 500, GasLimit: 4967974
          // Deposits: 1000, GasLimit: 9693977
          // Deposits: 1250, GasLimit: 12104647
          // Deposits: 1500, GasLimit: 14497133
          // Deposits: 1750, GasLimit: 16897584
          // Deposits: 2000, GasLimit: 19313720
          // Deposits: 2250, GasLimit: 21700950
          // Deposits: 2500, GasLimit: 24082428
          // Deposits: 2750, GasLimit: 26480028
          // Deposits: 3000, GasLimit: 28905377
          const listOfDeposits = [0, 7, 40, 50, 100, 300, 500, 250, 250, 250, 250, 250, 250, 250, 250]

          for (let index = 0; index < listOfDeposits.length; index++) {
            const element = listOfDeposits[index];
            await makeDeposits(element);

            const allIds = await atlasMine.getAllUserDepositIds(deposit.address);

            await treasure.functions['mint(address,uint256,uint256)'](deposit.address, tokenId, tokenAmount);
            await treasure.connect(deposit.signer).setApprovalForAll(atlasMine.address, true);

            let tx = await atlasMine.connect(deposit.signer).stakeTreasure(tokenId, tokenAmount);
            const gasLimit = tx.gasLimit.toString();
            console.log(`Deposits: ${allIds.length}, GasLimit: ${gasLimit}`);
          }
        })
      })

      describe('with NFTs staked', function () {
        beforeEach(async function () {
          for (let index = 0; index < boostScenarios.slice(0, -2).length; index++) {
            const scenario = boostScenarios[index];

            if (scenario.nft == legion.address) {
              await legion.mintWithId(staker1, scenario.tokenId);
              await legion.connect(staker1Signer).approve(atlasMine.address, scenario.tokenId);
              await atlasMine.connect(staker1Signer).stakeLegion(scenario.tokenId);
              expect(await legion.ownerOf(scenario.tokenId)).to.be.equal(atlasMine.address);
            } else {
              await treasure.functions['mint(address,uint256,uint256)'](staker1, scenario.tokenId, scenario.amount);
              await treasure.connect(staker1Signer).setApprovalForAll(atlasMine.address, true);
              await atlasMine.connect(staker1Signer).stakeTreasure(scenario.tokenId, scenario.amount);
              expect(await treasure.balanceOf(atlasMine.address, scenario.tokenId)).to.be.equal(scenario.amount);
            }
          }
        })

        it('Withdraw amount too big', async function () {
          const scenario = boostScenarios[0];
          await expect(atlasMine.connect(staker2Signer).unstakeTreasure(scenario.tokenId, scenario.amount))
            .to.be.revertedWith("Withdraw amount too big");
          expect(await treasure.balanceOf(atlasMine.address, scenario.tokenId)).to.be.equal(scenario.amount);
        })

        it('NFT is not staked', async function () {
          const scenario = boostScenarios[7];
          await expect(atlasMine.connect(staker2Signer).unstakeLegion(scenario.tokenId))
            .to.be.revertedWith("NFT is not staked");
        })

        it('unstake boosts', async function () {
          let totalBoost = await atlasMine.boosts(staker1);

          for (let index = 0; index < boostScenarios.slice(0, -2).length; index++) {
            const scenario = boostScenarios[index];
            const boostBefore = await atlasMine.boosts(staker1);

            if (scenario.nft == legion.address) {
              await atlasMine.connect(staker1Signer).unstakeLegion(scenario.tokenId);
              expect(await legion.ownerOf(scenario.tokenId)).to.be.equal(staker1);
            } else {
              await atlasMine.connect(staker1Signer).unstakeTreasure(scenario.tokenId, scenario.amount);
              expect(await treasure.balanceOf(staker1, scenario.tokenId)).to.be.equal(scenario.amount);
            }

            const boostAfter = await atlasMine.boosts(staker1);
            expect(boostBefore.sub(boostAfter)).to.be.equal(scenario.boost.mul(scenario.amount));
          }

          expect(await atlasMine.boosts(staker1)).to.be.equal(0);
        })

      })
    })
  })
});

import hre from 'hardhat';
import {expect} from 'chai';
import {getBlockTime, mineBlock, getCurrentTime} from './utils';

const {ethers, deployments, getNamedAccounts} = hre;
const { deploy } = deployments;

describe('TreasuryMine', function () {
  let treasuryMine: any, treasuryStake: any;
  let magicToken: any, lpToken: any;
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
    const ERC20Mintable = await ethers.getContractFactory('ERC20Mintable')
    magicToken = await ERC20Mintable.deploy()
    await magicToken.deployed();

    const ERC721Mintable = await ethers.getContractFactory('ERC721Mintable')
    lpToken = await ERC721Mintable.deploy()
    await lpToken.deployed();

    const TreasuryStake = await ethers.getContractFactory('TreasuryStake')
    treasuryStake = await TreasuryStake.deploy(magicToken.address, lpToken.address)
    await treasuryStake.deployed();

    const newOwner = deployer;
    const TreasuryMine = await ethers.getContractFactory('TreasuryMine')
    treasuryMine = await TreasuryMine.deploy(magicToken.address, treasuryStake.address, newOwner)
    await treasuryMine.deployed();
  });

  checkDeposit = async (
    tx: any,
    user: any,
    depositAmount: any,
    lock: any,
    magicTotalDepositsPrev: any,
    totalLpTokenPrev: any,
    currentIdPrev: any,
    allUserDepositIdsLenPrev: any,
  ) => {
    allUserDepositIdsLenPrev = ethers.BigNumber.from(allUserDepositIdsLenPrev);
    const locks = [2, 5, 20];
    const currentId = currentIdPrev.add(1);
    const lpAmount = depositAmount.add(depositAmount.mul(locks[lock]).div(10));
    expect(await treasuryMine.magicTotalDeposits()).to.be.equal(magicTotalDepositsPrev.add(depositAmount));
    expect(await treasuryMine.totalLpToken()).to.be.equal(totalLpTokenPrev.add(lpAmount));
    expect(await treasuryMine.currentId(user)).to.be.equal(currentId);
    const allUserDepositIds = await treasuryMine.getAllUserDepositIds(user);
    expect(await treasuryMine.depositIdIndex(user, currentId)).to.be.equal(allUserDepositIds.length - 1);
    expect(allUserDepositIds.length).to.be.equal(allUserDepositIdsLenPrev.add(1));
    expect(allUserDepositIds[allUserDepositIds.length - 1]).to.be.equal(currentId);

    const userInfo = await treasuryMine.userInfo(user, currentId);
    expect(userInfo.depositAmount).to.be.equal(depositAmount);
    expect(userInfo.lpAmount).to.be.equal(lpAmount);
    const locksTime = [await treasuryMine.TWO_WEEKS(), await treasuryMine.ONE_MONTH(), await treasuryMine.THREE_MONTHS()];
    const blockTimestamp = await getBlockTime(tx.blockNumber);
    expect(userInfo.lockedUntil).to.be.equal(locksTime[lock].add(blockTimestamp));
    expect(userInfo.rewardDebt).to.be.equal((await treasuryMine.accMagicPerShare()).mul(lpAmount).div(await treasuryMine.ONE()));
  }

  checkPendingRewardsPosition = async (
    wallet: any,
    timeDelta: any,
  ) => {
    let magicReward = (await treasuryMine.magicPerSecond()).mul(timeDelta);
    magicReward = magicReward.sub(magicReward.div(10));

    const userInfo = await treasuryMine.userInfo(wallet, 1);
    const ONE = await treasuryMine.ONE();
    const lpSupply = await treasuryMine.totalLpToken();
    let accMagicPerShare = await treasuryMine.accMagicPerShare();
    accMagicPerShare = accMagicPerShare.add(magicReward.mul(ONE).div(lpSupply));
    const pending = userInfo.lpAmount.mul(accMagicPerShare).div(ONE).sub(userInfo.rewardDebt);
    // const pending = userInfo.lpAmount.mul(magicReward.mul(ONE).div(lpSupply)).div(ONE).sub(userInfo.rewardDebt);
    expect(await treasuryMine.pendingRewardsPosition(wallet, 1)).to.be.equal(pending)
  }

  checkIndexes = async (
    wallet: any,
    currentId: any,
    depositId: any,
    depositIdIndex: any,
    allUserDepositIdsLen: any,
    allUserDepositIdsExpected: any,
    depositAmount: any,
    lock: any
  ) => {
    expect(await treasuryMine.currentId(wallet)).to.be.equal(currentId);
    expect(await treasuryMine.depositIdIndex(wallet, depositId)).to.be.equal(depositIdIndex);
    const allUserDepositIds = await treasuryMine.getAllUserDepositIds(wallet);
    expect(allUserDepositIds.length).to.be.equal(allUserDepositIdsLen);
    for (let index = 0; index < allUserDepositIds.length; index++) {
      const element = allUserDepositIds[index];
      expect(element).to.be.equal(allUserDepositIdsExpected[index]);
    }
  }

  it('init()', async function () {
    expect(await treasuryMine.isInitialized()).to.be.false;
    const rewards = ethers.utils.parseUnits('10', 'ether');
    await magicToken.mint(treasuryMine.address, rewards)
    let tx = await treasuryMine.init();
    tx = await tx.wait();
    const blockTimestamp = await getBlockTime(tx.blockNumber);
    const LIFECYCLE = await treasuryMine.LIFECYCLE();
    expect(await treasuryMine.isInitialized()).to.be.true;

    expect(await magicToken.balanceOf(treasuryMine.address)).to.be.equal(rewards);
    expect(await treasuryMine.endTimestamp()).to.be.equal(LIFECYCLE.add(blockTimestamp));
    expect(await treasuryMine.maxMagicPerSecond()).to.be.equal(rewards.div(LIFECYCLE));

    await expect(treasuryMine.init()).to.be.revertedWith("Cannot init again");
  });

  it('getBoost()', async function () {
    expect((await treasuryMine.getBoost(0)).boost).to.be.equal(ethers.utils.parseUnits('0.2', 'ether'));
    expect((await treasuryMine.getBoost(1)).boost).to.be.equal(ethers.utils.parseUnits('0.5', 'ether'));
    expect((await treasuryMine.getBoost(2)).boost).to.be.equal(ethers.utils.parseUnits('2', 'ether'));
  });

  it('deposit()', async function () {
    const magicTotalDepositsPrev = await treasuryMine.magicTotalDeposits();
    const totalLpTokenPrev = await treasuryMine.totalLpToken();
    const currentIdPrev = await treasuryMine.currentId(staker1);
    const allUserDepositIdsLenPrev = (await treasuryMine.getAllUserDepositIds(staker1)).length;

    const depositAmount = ethers.utils.parseUnits('10', 'ether');
    await magicToken.mint(staker1, depositAmount)
    await magicToken.connect(staker1Signer).approve(treasuryMine.address, depositAmount);

    expect(await treasuryMine.isInitialized()).to.be.false;
    await expect(treasuryMine.connect(staker1Signer).deposit(depositAmount, 0)).to.be.revertedWith("Not initialized");
    const rewards = ethers.utils.parseUnits('10', 'ether');
    await magicToken.mint(treasuryMine.address, rewards)
    await treasuryMine.init();
    expect(await treasuryMine.isInitialized()).to.be.true;

    let tx = await treasuryMine.connect(staker1Signer).deposit(depositAmount, 0);
    tx = await tx.wait();
    const blockTimestamp = await getBlockTime(tx.blockNumber);
    const lpAmount = depositAmount.add(depositAmount.mul(2).div(10));

    await checkDeposit(
      tx,
      staker1,
      depositAmount,
      0,
      magicTotalDepositsPrev,
      totalLpTokenPrev,
      currentIdPrev,
      allUserDepositIdsLenPrev
    )
  });

  describe('with init and deposits', function () {
    const deposit1 = ethers.utils.parseUnits('50', 'ether');
    const lock1 = 2;
    const deposit2 = ethers.utils.parseUnits('100', 'ether');
    const lock2 = 1;
    const deposit3 = ethers.utils.parseUnits('500', 'ether');
    const lock3 = 0;
    let depositTimestamp = [0, 0, 0,];
    let deposits: any;

    let initTimestamp: any;
    let rewards: any;

    beforeEach(async function () {
      rewards = ethers.utils.parseUnits('2500', 'ether');
      await magicToken.mint(treasuryMine.address, rewards)
      let tx = await treasuryMine.init();
      tx = await tx.wait();
      initTimestamp = await getBlockTime(tx.blockNumber);

      deposits = [
        [staker1, staker1Signer, deposit1, lock1],
        [staker2, staker2Signer, deposit2, lock2],
        [staker3, staker3Signer, deposit3, lock3],
      ]

      for (let index = 0; index < deposits.length; index++) {
        const staker = deposits[index][0];
        const stakerSigner = deposits[index][1];
        const depositAmount = deposits[index][2];
        const lock = deposits[index][3];

        const magicTotalDepositsPrev = await treasuryMine.magicTotalDeposits();
        const totalLpTokenPrev = await treasuryMine.totalLpToken();
        const currentIdPrev = await treasuryMine.currentId(staker);
        const allUserDepositIdsLenPrev = (await treasuryMine.getAllUserDepositIds(staker)).length;

        await magicToken.mint(staker, depositAmount)
        await magicToken.connect(stakerSigner).approve(treasuryMine.address, depositAmount);
        let tx = await treasuryMine.connect(stakerSigner).deposit(depositAmount, lock);
        tx = await tx.wait();
        depositTimestamp[index] = await getBlockTime(tx.blockNumber);

        await checkDeposit(
          tx,
          staker,
          depositAmount,
          lock,
          magicTotalDepositsPrev,
          totalLpTokenPrev,
          currentIdPrev,
          allUserDepositIdsLenPrev
        )
      }
    });

    it('addExcludedAddress() && removeExcludedAddress()', async function () {
      const totalSupply = await magicToken.totalSupply();
      const magicTotalDeposits = await treasuryMine.magicTotalDeposits();
      const bal = await magicToken.balanceOf(treasuryMine.address);
      const rewards = bal.sub(magicTotalDeposits);
      const circulatingSupply = totalSupply.sub(rewards);
      const ONE = await treasuryMine.ONE();
      const util = await treasuryMine.utilization();
      expect(magicTotalDeposits.mul(ONE).div(circulatingSupply)).to.be.equal(util);

      await magicToken.mint(deployer, magicTotalDeposits);
      const newUtil = await treasuryMine.utilization();
      expect(newUtil).to.be.equal("499999888710850981");

      await treasuryMine.addExcludedAddress(deployer);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([deployer]);
      expect(await treasuryMine.utilization()).to.be.equal("999999455919890831");

      await treasuryMine.addExcludedAddress(staker1);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker1]);

      await treasuryMine.addExcludedAddress(staker2);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker1, staker2]);

      await treasuryMine.addExcludedAddress(staker3);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker1, staker2, staker3]);

      await treasuryMine.removeExcludedAddress(staker1);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([deployer, staker3, staker2]);

      await treasuryMine.removeExcludedAddress(deployer);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([staker2, staker3]);

      await treasuryMine.removeExcludedAddress(staker3);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([staker2]);

      await expect(treasuryMine.removeExcludedAddress(staker3)).to.be.revertedWith("address not excluded");

      await treasuryMine.removeExcludedAddress(staker2);
      expect(await treasuryMine.getExcludedAddresses()).to.be.deep.equal([]);

      await expect(treasuryMine.removeExcludedAddress(staker2)).to.be.revertedWith("no excluded addresses");

      expect(await treasuryMine.utilization()).to.be.equal("499999772475570454");
      await treasuryMine.addExcludedAddress(deployer);
      expect(await treasuryMine.utilization()).to.be.equal("999999010763878240");
    });

    it('pendingRewardsPosition()', async function () {
      const timeDelta = 600;
      await mineBlock(depositTimestamp[2] + timeDelta);
      let magicTotalDeposits = ethers.utils.parseUnits('0', 'ether')
      let totalLpToken = ethers.utils.parseUnits('0', 'ether')

      for (let index = 0; index < deposits.length; index++) {
        const wallet = deposits[index][0];
        await checkPendingRewardsPosition(wallet, timeDelta)

        await checkIndexes(
          wallet, // user
          1, // currentId
          1, // depositId
          0, // depositIdIndex
          1, // allUserDepositIdsLen
          [1], // allUserDepositIdsExpected
          deposits[index][2], // depositAmount
          deposits[index][3] // lock
        )

        magicTotalDeposits = magicTotalDeposits.add(deposits[index][2]);
        const locks = [2, 5, 20];
        totalLpToken = totalLpToken.add(deposits[index][2])
          .add(deposits[index][2].mul(locks[deposits[index][3]]).div(10))
      }

      expect(await treasuryMine.magicTotalDeposits()).to.be.equal(magicTotalDeposits);
      expect(await treasuryMine.totalLpToken()).to.be.equal(totalLpToken);
    });

    it('pendingRewardsAll()', async function () {
      const timeDelta = 600;
      await mineBlock(depositTimestamp[2] + timeDelta);
      let magicTotalDeposits = ethers.utils.parseUnits('0', 'ether')
      let totalLpToken = ethers.utils.parseUnits('0', 'ether')

      for (let index = 0; index < deposits.length; index++) {
        const wallet = deposits[index][0];
        let magicReward = (await treasuryMine.magicPerSecond()).mul(timeDelta);
        magicReward = magicReward.sub(magicReward.div(10));
        const userInfo = await treasuryMine.userInfo(wallet, 1);
        const ONE = await treasuryMine.ONE();
        const lpSupply = await treasuryMine.totalLpToken();
        let accMagicPerShare = await treasuryMine.accMagicPerShare();
        accMagicPerShare = accMagicPerShare.add(magicReward.mul(ONE).div(lpSupply));
        const pending = userInfo.lpAmount.mul(accMagicPerShare).div(ONE).sub(userInfo.rewardDebt);
        expect(await treasuryMine.pendingRewardsAll(wallet)).to.be.equal(pending)

        await checkIndexes(
          wallet, // user
          1, // currentId
          1, // depositId
          0, // depositIdIndex
          1, // allUserDepositIdsLen
          [1], // allUserDepositIdsExpected
          deposits[index][2], // depositAmount
          deposits[index][3] // lock
        )

        magicTotalDeposits = magicTotalDeposits.add(deposits[index][2]);
        const locks = [2, 5, 20];
        totalLpToken = totalLpToken.add(deposits[index][2])
          .add(deposits[index][2].mul(locks[deposits[index][3]]).div(10))
      }

      expect(await treasuryMine.magicTotalDeposits()).to.be.equal(magicTotalDeposits);
      expect(await treasuryMine.totalLpToken()).to.be.equal(totalLpToken);
    });

    it('withdrawPosition()', async function () {
      let timeDelta = 60 * 60 * 24 * 31;
      let tx: any;
      await mineBlock(depositTimestamp[2] + timeDelta);
      let magicTotalDeposits = ethers.utils.parseUnits('0', 'ether')
      let totalLpToken = ethers.utils.parseUnits('0', 'ether')

      for (let index = 0; index < deposits.length; index++) {
        const staker = deposits[index][0];
        const stakerSigner = deposits[index][1];
        const depositAmount = deposits[index][2];
        const lock = deposits[index][3];
        if (index == 0) {
          await expect(treasuryMine.connect(stakerSigner).withdrawPosition(1, depositAmount)).to.be.revertedWith("Position is still locked")
        } else {
          await treasuryMine.connect(stakerSigner).withdrawPosition(1, depositAmount);
        }
        timeDelta = (await getCurrentTime()) - depositTimestamp[2];

        await checkPendingRewardsPosition(staker, timeDelta)
      }

      expect(await treasuryMine.magicTotalDeposits()).to.be.equal(deposits[0][2]);
      const lpAmount = deposits[0][2].add(deposits[0][2].mul(20).div(10));
      expect(await treasuryMine.totalLpToken()).to.be.equal(lpAmount);
    });

    describe('with second wave of deposits', function () {
      const secondDeposit1 = ethers.utils.parseUnits('200', 'ether');
      const secondLock1 = 1;
      const secondDeposit2 = ethers.utils.parseUnits('300', 'ether');
      const secondLock2 = 2;
      let secondDepositTimestamp = [0, 0, 0,];
      let secondDeposits: any;
      let depositsAll: any;

      beforeEach(async function () {
        depositsAll = [
          [staker1, staker1Signer, deposit1.add(secondDeposit1), lock1],
          [staker2, staker2Signer, deposit2.add(secondDeposit2), lock2],
          [staker3, staker3Signer, deposit3, lock3],
        ]

        secondDeposits = [
          [staker1, staker1Signer, secondDeposit1, secondLock1],
          [staker2, staker2Signer, secondDeposit2, secondLock2],
        ]

        for (let index = 0; index < secondDeposits.length; index++) {
          const staker = secondDeposits[index][0];
          const stakerSigner = secondDeposits[index][1];
          const depositAmount = secondDeposits[index][2];
          const lock = secondDeposits[index][3];

          const magicTotalDepositsPrev = await treasuryMine.magicTotalDeposits();
          const totalLpTokenPrev = await treasuryMine.totalLpToken();
          const currentIdPrev = await treasuryMine.currentId(staker);
          const allUserDepositIdsLenPrev = (await treasuryMine.getAllUserDepositIds(staker)).length;

          await magicToken.mint(staker, depositAmount)
          await magicToken.connect(stakerSigner).approve(treasuryMine.address, depositAmount);
          let tx = await treasuryMine.connect(stakerSigner).deposit(depositAmount, lock);
          tx = await tx.wait();
          depositTimestamp[index] = await getBlockTime(tx.blockNumber);

          await checkDeposit(
            tx,
            staker,
            depositAmount,
            lock,
            magicTotalDepositsPrev,
            totalLpTokenPrev,
            currentIdPrev,
            allUserDepositIdsLenPrev
          )

          await checkIndexes(
            staker, // user
            2, // currentId
            2, // depositId
            1, // depositIdIndex
            2, // allUserDepositIdsLen
            [1, 2], // allUserDepositIdsExpected
            secondDeposits[index][2], // depositAmount
            secondDeposits[index][3] // lock
          )
        }
      });

      it('withdrawAll()', async function () {
        let timeDelta = 60 * 60 * 24 * 91;
        let tx: any;
        await mineBlock(parseInt(initTimestamp) + timeDelta);
        const currentTime = await getCurrentTime();
        expect(await treasuryMine.endTimestamp()).to.be.lt(currentTime)

        for (let index = 0; index < deposits.length; index++) {
          const staker = deposits[index][0];
          const stakerSigner = deposits[index][1];
          const depositAmount = deposits[index][2];
          const lock = deposits[index][3];
          const pendingRewardsAll = await treasuryMine.pendingRewardsAll(staker);
          const allUserDepositIds = await treasuryMine.getAllUserDepositIds(staker);
          let totalAmount = ethers.BigNumber.from(0);
          expect(await magicToken.balanceOf(staker)).to.be.equal(0);
          for (let i = 0; i < allUserDepositIds.length; i++) {
            const userInfo = await treasuryMine.userInfo(staker, allUserDepositIds[i]);
            totalAmount = totalAmount.add(userInfo.depositAmount);
          }
          let tx = await treasuryMine.connect(stakerSigner).withdrawAll();
          expect(await magicToken.balanceOf(staker)).to.be.equal(totalAmount);
          expect(await treasuryMine.pendingRewardsAll(staker)).to.be.equal(pendingRewardsAll);
        }
      });

      describe('with block mined', function () {
        it('harvestPosition()', async function () {
          let timeDelta = 60 * 60 * 24 * 20;
          for (let index = 0; index < deposits.length; index++) {
            const currentTime = await getCurrentTime();
            await mineBlock(currentTime + timeDelta);

            const stakerSigner = deposits[index][1];
            await treasuryMine.connect(stakerSigner).harvestPosition(1);
          }

          for (let index = 0; index < secondDeposits.length; index++) {
            const currentTime = await getCurrentTime();
            await mineBlock(currentTime + timeDelta);

            const stakerSigner = deposits[index][1];
            await treasuryMine.connect(stakerSigner).harvestPosition(2);
          }

          for (let index = 0; index < deposits.length; index++) {
            const stakerSigner = deposits[index][1];
            await treasuryMine.connect(stakerSigner).harvestPosition(1);
          }

          for (let index = 0; index < secondDeposits.length; index++) {
            const stakerSigner = deposits[index][1];
            await treasuryMine.connect(stakerSigner).harvestPosition(2);
          }

          const totalRewardsEarned = await treasuryMine.totalRewardsEarned();
          const magicTotalDeposits = await treasuryMine.magicTotalDeposits();

          const treasuryStakeBal = await magicToken.balanceOf(await treasuryMine.treasuryStake())
          expect(treasuryStakeBal.div(1000)).to.be.equal(totalRewardsEarned.div(9).div(1000))

          const currentBalance = await magicToken.balanceOf(treasuryMine.address);
          const expectedBalance = rewards
            .sub(totalRewardsEarned)
            .sub(totalRewardsEarned.div(9))
            .add(magicTotalDeposits)

          expect(currentBalance.div(100000)).to.be.equal(expectedBalance.div(100000));

        });

        it('harvestAll()', async function () {
          let timeDelta = 60 * 60 * 24 * 91;
          const currentTime = await getCurrentTime();
          await mineBlock(currentTime + timeDelta);
          expect(await treasuryMine.endTimestamp()).to.be.lt(await getCurrentTime())

          const magicTotalDeposits = await treasuryMine.magicTotalDeposits();
          const ONE = await treasuryMine.ONE();
          const utilization = magicTotalDeposits.mul(ONE).div(await magicToken.totalSupply());
          console.log('utilization', utilization.toString())
          const magicPerSecond = await treasuryMine.magicPerSecond();
          const maxMagicPerSecond = await treasuryMine.maxMagicPerSecond();
          console.log('magicPerSecond', magicPerSecond.toString())
          console.log('maxMagicPerSecond', maxMagicPerSecond.toString())
          const endTimestamp = await treasuryMine.endTimestamp();
          console.log('endTimestamp', endTimestamp.toString())
          console.log('start', endTimestamp.sub(await treasuryMine.LIFECYCLE()).toString())
          console.log('now', currentTime.toString())

          for (let index = 0; index < deposits.length; index++) {
            const staker = deposits[index][0];
            const stakerSigner = deposits[index][1];
            const depositAmount = deposits[index][2];
            const lock = deposits[index][3];

            const balBefore = await magicToken.balanceOf(staker);
            expect(balBefore).to.be.equal(0);

            const pendingRewardsAll = await treasuryMine.pendingRewardsAll(staker);
            await treasuryMine.connect(stakerSigner).harvestAll();
            const balAfter = await magicToken.balanceOf(staker);
            expect(balAfter.sub(balBefore)).to.be.equal(pendingRewardsAll);
            expect(await treasuryMine.pendingRewardsAll(staker)).to.be.equal(0);
          }
          const totalRewardsEarned = await treasuryMine.totalRewardsEarned();
          console.log('rewards', rewards.toString())
          console.log('totalRewardsEarned', totalRewardsEarned.toString())
          console.log('magicTotalDeposits', magicTotalDeposits.toString())

          const currentBalance = await magicToken.balanceOf(treasuryMine.address);
          const expectedBalance = rewards
            .sub(totalRewardsEarned)
            .sub(totalRewardsEarned.div(9))
            .add(magicTotalDeposits)

          expect(currentBalance.div(100000)).to.be.equal(expectedBalance.div(100000));
        });

        it('withdrawAndHarvestPosition()', async function () {
          let timeDelta = 60 * 60 * 24 * 95;
          const currentTime = await getCurrentTime();
          await mineBlock(currentTime + timeDelta);

          for (let index = 0; index < deposits.length; index++) {
            const staker = deposits[index][0];
            const stakerSigner = deposits[index][1];
            let depositAmount;
            if (index == 2)
              depositAmount = [deposits[index][2]];
            else
              depositAmount = [deposits[index][2], secondDeposits[index][2]];
            const lock = deposits[index][3];

            const depositIds = await treasuryMine.getAllUserDepositIds(staker);

            const pendingRewardsAll = await treasuryMine.pendingRewardsAll(staker);
            expect(await magicToken.balanceOf(staker)).to.be.equal(0);

            for (let i = 0; i < depositIds.length; i++) {
              const balBefore = await magicToken.balanceOf(staker);
              const pendingRewardsPosition = await treasuryMine.pendingRewardsPosition(staker, depositIds[i]);
              await treasuryMine.connect(stakerSigner).withdrawAndHarvestPosition(depositIds[i], depositAmount[i].div(2));
              await treasuryMine.connect(stakerSigner).withdrawAndHarvestPosition(depositIds[i], depositAmount[i].div(2));
              const balAfter = await magicToken.balanceOf(staker);
              expect(balAfter.sub(balBefore)).to.be.equal(pendingRewardsPosition.add(depositAmount[i]));
            }

            expect(await treasuryMine.pendingRewardsAll(staker)).to.be.equal(0);
            expect(await magicToken.balanceOf(staker)).to.be.equal(depositsAll[index][2].add(pendingRewardsAll));
            expect((await treasuryMine.getAllUserDepositIds(staker)).length).to.be.equal(0)
          }
        });

        it('withdrawAndHarvestAll()', async function () {
          let timeDelta = 60 * 60 * 24 * 95;
          const currentTime = await getCurrentTime();
          await mineBlock(currentTime + timeDelta);

          for (let index = 0; index < depositsAll.length; index++) {
            const staker = depositsAll[index][0];
            const stakerSigner = depositsAll[index][1];
            const depositAmount = depositsAll[index][2];
            const lock = depositsAll[index][3];

            const pendingRewardsAll = await treasuryMine.pendingRewardsAll(staker);

            expect(await magicToken.balanceOf(staker)).to.be.equal(0);

            await treasuryMine.connect(stakerSigner).withdrawAndHarvestAll();

            expect(await magicToken.balanceOf(staker)).to.be.equal(depositAmount.add(pendingRewardsAll));

            const depositIds = await treasuryMine.getAllUserDepositIds(staker);
            expect(depositIds.length).to.be.equal(0)
          }
        });

        it('burnLeftovers()', async function () {
          await expect(treasuryMine.connect(staker1Signer).burnLeftovers())
            .to.be.revertedWith("Will not burn before end");

          let timeDelta = 60 * 60 * 24 * 95;
          const currentTime = await getCurrentTime();
          await mineBlock(currentTime + timeDelta);

          const expectedBalances = [0, 0, 0]

          for (let index = 0; index < depositsAll.length; index++) {
            const staker = depositsAll[index][0];
            expectedBalances[index] = await treasuryMine.pendingRewardsAll(staker);
          }

          const blackhole = "0x000000000000000000000000000000000000dEaD";
          expect(await magicToken.balanceOf(blackhole)).to.be.equal(0);

          await treasuryMine.connect(staker1Signer).burnLeftovers();

          const totalRewardsEarned = await treasuryMine.totalRewardsEarned();
          const expectedBurn = rewards
            .sub(totalRewardsEarned)
            .sub(totalRewardsEarned.div(9))
          const actualBalance = await magicToken.balanceOf(blackhole);
          expect(actualBalance.div(100000000)).to.be.equal(expectedBurn.div(100000000));

          for (let index = 0; index < depositsAll.length; index++) {
            const staker = depositsAll[index][0];
            const stakerSigner = depositsAll[index][1];
            const depositAmount = depositsAll[index][2];
            const lock = depositsAll[index][3];

            const pendingRewardsAll = await treasuryMine.pendingRewardsAll(staker);
            expect(await magicToken.balanceOf(staker)).to.be.equal(0);

            await treasuryMine.connect(stakerSigner).withdrawAndHarvestAll();

            expect(await magicToken.balanceOf(staker)).to.be.equal(depositAmount.add(pendingRewardsAll));
            const depositIds = await treasuryMine.getAllUserDepositIds(staker);
            expect(depositIds.length).to.be.equal(0)
          }

          // some rounding errors are expected
          expect(await magicToken.balanceOf(treasuryMine.address)).to.be.lt(10000000);
        });

        it('kill()', async function () {
          await expect(treasuryMine.connect(staker1Signer).kill())
            .to.be.revertedWith("Ownable: caller is not the owner");

          expect(await magicToken.balanceOf(deployer)).to.be.equal(0);
          await treasuryMine.kill();
          const totalRewardsEarned = await treasuryMine.totalRewardsEarned();

          const expectedToken = rewards
            .sub(totalRewardsEarned)
            .sub(totalRewardsEarned.div(9))
          const actualBalance = await magicToken.balanceOf(deployer);
          expect(actualBalance.div(100000000)).to.be.equal(expectedToken.div(100000000));

          for (let index = 0; index < depositsAll.length; index++) {
            const staker = depositsAll[index][0];
            const stakerSigner = depositsAll[index][1];
            const depositAmount = depositsAll[index][2];
            const lock = depositsAll[index][3];

            const pendingRewardsAll = await treasuryMine.pendingRewardsAll(staker);
            expect(await magicToken.balanceOf(staker)).to.be.equal(0);

            await treasuryMine.connect(stakerSigner).withdrawAndHarvestAll();

            expect(await magicToken.balanceOf(staker)).to.be.equal(depositAmount.add(pendingRewardsAll));
            const depositIds = await treasuryMine.getAllUserDepositIds(staker);
            expect(depositIds.length).to.be.equal(0)
          }

          // some rounding errors are expected
          expect(await magicToken.balanceOf(treasuryMine.address)).to.be.lt(10000000);

          await expect(treasuryMine.kill()).to.be.revertedWith("Already dead");

          let timeDelta = 60 * 60 * 24 * 95;
          const currentTime = await getCurrentTime();
          await mineBlock(currentTime + timeDelta);

          await expect(treasuryMine.kill()).to.be.revertedWith("Will not kill after end");

        });
      })
    })
  })
});

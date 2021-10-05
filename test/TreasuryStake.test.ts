import hre from 'hardhat';
import {expect} from 'chai';

const {ethers, deployments, getNamedAccounts} = hre;
const { deploy } = deployments;

describe('TreasuryStake', function () {
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
    tokenId: any,
    user: any,
    totalLpTokenPrev: any,
    allUserDepositIdsLenPrev: any,
  ) => {

    allUserDepositIdsLenPrev = ethers.BigNumber.from(allUserDepositIdsLenPrev);
    const lpAmount = await treasuryStake.getLpAmount(tokenId);
    expect(await treasuryStake.totalLpToken()).to.be.equal(totalLpTokenPrev.add(lpAmount));
    const allUserDepositIds = await treasuryStake.getAllUserTokenIds(user);
    expect(allUserDepositIds[allUserDepositIds.length - 1]).to.be.equal(tokenId);
    expect(allUserDepositIds.length).to.be.equal(allUserDepositIdsLenPrev.add(1));
    expect(await treasuryStake.tokenIdIndex(user, tokenId)).to.be.equal(allUserDepositIds.length - 1);

    const userInfo = await treasuryStake.userInfo(user, tokenId);
    expect(userInfo.tokenId).to.be.equal(tokenId);
    expect(userInfo.lpAmount).to.be.equal(lpAmount);
    expect(userInfo.rewardDebt).to.be.equal((await treasuryStake.accMagicPerShare()).mul(lpAmount).div(await treasuryMine.ONE()));
  }

  checkIndexes = async (
    wallet: any,
    tokenId: any,
    tokenIdIndex: any,
    allUserTokenIdsLen: any,
    allUserTokenIdsExpected: any,
  ) => {
    expect(await treasuryStake.tokenIdIndex(wallet, tokenId)).to.be.equal(tokenIdIndex);
    const allUserTokenIds = await treasuryStake.getAllUserTokenIds(wallet);
    expect(allUserTokenIds.length).to.be.equal(allUserTokenIdsLen);
    for (let index = 0; index < allUserTokenIds.length; index++) {
      const element = allUserTokenIds[index];
      expect(element).to.be.equal(allUserTokenIdsExpected[index]);
    }
  }

  it('getBoost()');

  it('deposit()', async function () {
    const totalLpTokenPrev = await treasuryStake.totalLpToken();
    const allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker1)).length;

    const tokenId = await lpToken.totalSupply();
    await lpToken.mint(staker1)
    await lpToken.connect(staker1Signer).approve(treasuryStake.address, tokenId);
    await treasuryStake.connect(staker1Signer).deposit(tokenId);
    const lpAmount = await treasuryStake.getLpAmount(tokenId);

    await checkDeposit(
      tokenId,
      staker1,
      totalLpTokenPrev,
      allUserDepositIdsLenPrev
    );

    await checkIndexes(
      staker1, // wallet
      tokenId, // tokenId
      0, // tokenIdIndex
      1, // allUserTokenIdsLen
      [tokenId], // allUserTokenIdsExpected
    )
  });

  it('notifyRewards()', async function () {
    const rewards = ethers.utils.parseUnits('100', 'ether');
    await magicToken.mint(deployer, rewards);
    await magicToken.approve(treasuryStake.address, rewards);
    await treasuryStake.notifyRewards(rewards);

    expect(await treasuryStake.totalLpToken()).to.be.equal(0);
    expect(await treasuryStake.accMagicPerShare()).to.be.equal(0);
    expect(await treasuryStake.undistributedRewards()).to.be.equal(rewards);

    const tokenId = await lpToken.totalSupply();
    await lpToken.mint(staker1)
    await lpToken.connect(staker1Signer).approve(treasuryStake.address, tokenId);
    await treasuryStake.connect(staker1Signer).deposit(tokenId);
    const lpAmount = await treasuryStake.getLpAmount(tokenId);

    await treasuryStake.notifyRewards(0);

    const ONE = await treasuryStake.ONE();
    expect(await treasuryStake.totalLpToken()).to.be.equal(lpAmount);
    expect(await treasuryStake.accMagicPerShare()).to.be.equal(
      rewards.mul(ONE).div(lpAmount)
    );
    expect(await treasuryStake.undistributedRewards()).to.be.equal(0);
  });

  describe('with deposits', function () {
    let deposits: any;

    beforeEach(async function () {
      deposits = [
        [staker1, staker1Signer, 0],
        [staker2, staker2Signer, 0],
        [staker3, staker3Signer, 0],
      ]

      for (let index = 0; index < deposits.length; index++) {
        const staker = deposits[index][0];
        const stakerSigner = deposits[index][1];

        const totalLpTokenPrev = await treasuryStake.totalLpToken();
        const allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker)).length;

        const tokenId = await lpToken.totalSupply();
        deposits[index][2] = tokenId;
        await lpToken.mint(staker)
        await lpToken.connect(stakerSigner).approve(treasuryStake.address, tokenId);
        let tx = await treasuryStake.connect(stakerSigner).deposit(tokenId);
        tx = await tx.wait();
        const lpAmount = await treasuryStake.getLpAmount(tokenId);

        await checkDeposit(
          tokenId,
          staker,
          totalLpTokenPrev,
          allUserDepositIdsLenPrev
        );

        await checkIndexes(
          staker, // wallet
          tokenId, // tokenId
          0, // tokenIdIndex
          1, // allUserTokenIdsLen
          [tokenId], // allUserTokenIdsExpected
        )
      }
    });

    it('withdrawPosition()', async function () {
      let totalLpToken = ethers.utils.parseUnits('0', 'ether')

      for (let index = 0; index < deposits.length; index++) {
        const staker = deposits[index][0];
        const stakerSigner = deposits[index][1];
        const tokenId = deposits[index][2];
        const totalLpTokenPrev = await treasuryStake.totalLpToken();
        const userInfoPrev = await treasuryStake.userInfo(staker, tokenId);

        await treasuryStake.connect(stakerSigner).withdrawPosition(tokenId);

        const userInfo = await treasuryStake.userInfo(staker, tokenId);
        expect(await treasuryStake.totalLpToken()).to.be.equal(totalLpTokenPrev.sub(userInfoPrev.lpAmount));
        expect(userInfo.tokenId).to.be.equal(0);
        expect(userInfo.lpAmount).to.be.equal(0);
        expect(userInfo.rewardDebt).to.be.equal(0);
      }
    });

    describe('with second wave of deposits', function () {
      let secondDeposits: any;

      beforeEach(async function () {
        secondDeposits = [
          [staker1, staker1Signer, 0],
          [staker2, staker2Signer, 0],
          [staker3, staker3Signer, 0],
        ]

        for (let index = 0; index < secondDeposits.length; index++) {
          const staker = secondDeposits[index][0];
          const stakerSigner = secondDeposits[index][1];

          const totalLpTokenPrev = await treasuryStake.totalLpToken();
          const allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker)).length;

          const tokenId = await lpToken.totalSupply();
          secondDeposits[index][2] = tokenId;
          await lpToken.mint(staker)
          await lpToken.connect(stakerSigner).approve(treasuryStake.address, tokenId);
          let tx = await treasuryStake.connect(stakerSigner).deposit(tokenId);
          tx = await tx.wait();
          const lpAmount = await treasuryStake.getLpAmount(tokenId);

          await checkDeposit(
            tokenId,
            staker,
            totalLpTokenPrev,
            allUserDepositIdsLenPrev
          );

          await checkIndexes(
            staker, // wallet
            tokenId, // tokenId
            1, // tokenIdIndex
            2, // allUserTokenIdsLen
            [deposits[index][2], tokenId], // allUserTokenIdsExpected
          )
        }
      });

      it('withdrawAll()', async function () {
        for (let index = 0; index < deposits.length; index++) {
          const staker = deposits[index][0];
          const stakerSigner = deposits[index][1];
          const tokenId = [deposits[index][2], secondDeposits[index][2]];
          const totalLpTokenPrev = await treasuryStake.totalLpToken();
          const userInfoPrev1 = await treasuryStake.userInfo(staker, tokenId[0]);
          const userInfoPrev2 = await treasuryStake.userInfo(staker, tokenId[1]);

          await treasuryStake.connect(stakerSigner).withdrawAll();

          expect(await treasuryStake.totalLpToken()).to.be.equal(
            totalLpTokenPrev.sub(userInfoPrev1.lpAmount).sub(userInfoPrev2.lpAmount)
          );

          for (let i = 0; i < 2; i++) {
            const userInfo = await treasuryStake.userInfo(staker, tokenId[i]);
            expect(userInfo.tokenId).to.be.equal(0);
            expect(userInfo.lpAmount).to.be.equal(0);
            expect(userInfo.rewardDebt).to.be.equal(0);

            await checkIndexes(
              staker, // wallet
              tokenId[i], // tokenId
              i, // tokenIdIndex
              2, // allUserTokenIdsLen
              [tokenId[0], tokenId[1]], // allUserTokenIdsExpected
            )
          }
        }
      });

      it('notifyRewards()', async function () {
        expect(await treasuryStake.undistributedRewards()).to.be.equal(0);
        expect(await treasuryStake.accMagicPerShare()).to.be.equal(0)

        const rewards = ethers.utils.parseUnits('100', 'ether');
        await magicToken.mint(deployer, rewards);
        await magicToken.approve(treasuryStake.address, rewards);
        await treasuryStake.notifyRewards(rewards);

        const totalLpToken = await treasuryStake.totalLpToken();
        const ONE = await treasuryStake.ONE();
        expect(await treasuryStake.accMagicPerShare()).to.be.equal(
          rewards.mul(ONE).div(totalLpToken)
        );
        expect(await treasuryStake.undistributedRewards()).to.be.equal(0);
      });

      describe('with rewards', function () {
        const rewards = ethers.utils.parseUnits('100', 'ether');

        beforeEach(async function () {
          await magicToken.mint(deployer, rewards);
          await magicToken.approve(treasuryStake.address, rewards);
          await treasuryStake.notifyRewards(rewards);
        });

        it('harvestPosition()', async function () {
          for (let index = 0; index < deposits.length; index++) {
            const staker = deposits[index][0];
            const stakerSigner = deposits[index][1];
            const tokenId = [deposits[index][2], secondDeposits[index][2]];

            const totalLpToken = await treasuryStake.totalLpToken();

            for (let i = 0; i < 2; i++) {
              const userInfo = await treasuryStake.userInfo(staker, tokenId[i]);
              const expectedRewards = rewards.mul(userInfo.lpAmount).div(totalLpToken);
              const actualRewards = await treasuryStake.pendingRewardsPosition(staker, tokenId[i]);
              expect(actualRewards.div(100)).to.be.equal(expectedRewards.div(100));

              const balBefore = await magicToken.balanceOf(staker);
              await treasuryStake.connect(stakerSigner).harvestPosition(tokenId[i]);
              const balAfter = await magicToken.balanceOf(staker);

              expect(balAfter.sub(balBefore)).to.be.equal(actualRewards);
            }
          }
        });

        it('harvestAll()', async function () {
          for (let index = 0; index < deposits.length; index++) {
            const staker = deposits[index][0];
            const stakerSigner = deposits[index][1];
            const tokenId = [deposits[index][2], secondDeposits[index][2]];

            const totalLpToken = await treasuryStake.totalLpToken();

            let expectedRewards = ethers.BigNumber.from(0);
            for (let i = 0; i < 2; i++) {
              const userInfo = await treasuryStake.userInfo(staker, tokenId[i]);
              expectedRewards = expectedRewards.add(rewards.mul(userInfo.lpAmount).div(totalLpToken));
            }

            const actualRewards = await treasuryStake.pendingRewardsAll(staker);
            expect(actualRewards.div(100)).to.be.equal(expectedRewards.div(100));

            const balBefore = await magicToken.balanceOf(staker);
            await treasuryStake.connect(stakerSigner).harvestAll();
            const balAfter = await magicToken.balanceOf(staker);

            expect(balAfter.sub(balBefore)).to.be.equal(actualRewards);
          }
        });

        it('withdrawAndHarvestPosition()', async function () {
          for (let index = 0; index < deposits.length; index++) {
            const staker = deposits[index][0];
            const stakerSigner = deposits[index][1];
            const tokenId = [deposits[index][2], secondDeposits[index][2]];

            const totalLpToken = await treasuryStake.totalLpToken();

            for (let i = 0; i < 2; i++) {
              const userInfo = await treasuryStake.userInfo(staker, tokenId[i]);
              const ONE = await treasuryStake.ONE();
              const accMagicPerShare = await treasuryStake.accMagicPerShare();
              const expectedRewards = userInfo.lpAmount.mul(accMagicPerShare).div(ONE).sub(userInfo.rewardDebt);
              const actualRewards = await treasuryStake.pendingRewardsPosition(staker, tokenId[i]);
              expect(actualRewards.div(100)).to.be.equal(expectedRewards.div(100));

              const balBefore = await magicToken.balanceOf(staker);
              expect(await lpToken.ownerOf(tokenId[i])).to.be.equal(treasuryStake.address);
              await treasuryStake.connect(stakerSigner).withdrawAndHarvestPosition(tokenId[i]);
              expect(await lpToken.ownerOf(tokenId[i])).to.be.equal(staker);
              const balAfter = await magicToken.balanceOf(staker);

              expect(balAfter.sub(balBefore)).to.be.equal(actualRewards);

              if (i == 0) {
                await checkIndexes(
                  staker, // wallet
                  tokenId[0], // tokenId
                  0, // tokenIdIndex
                  1, // allUserTokenIdsLen
                  [tokenId[1]], // allUserTokenIdsExpected
                )
              } else {
                await checkIndexes(
                  staker, // wallet
                  tokenId[1], // tokenId
                  0, // tokenIdIndex
                  0, // allUserTokenIdsLen
                  [], // allUserTokenIdsExpected
                )
              }
            }
          }
        });

        it('withdrawAndHarvestAll()', async function () {
          for (let index = 0; index < deposits.length; index++) {
            const staker = deposits[index][0];
            const stakerSigner = deposits[index][1];
            const tokenId = [deposits[index][2], secondDeposits[index][2]];

            let expectedRewards = ethers.BigNumber.from(0);
            for (let i = 0; i < 2; i++) {
              const userInfo = await treasuryStake.userInfo(staker, tokenId[i]);
              const ONE = await treasuryStake.ONE();
              const accMagicPerShare = await treasuryStake.accMagicPerShare();
              expectedRewards = expectedRewards.add(userInfo.lpAmount.mul(accMagicPerShare).div(ONE).sub(userInfo.rewardDebt));

              expect(await lpToken.ownerOf(tokenId[i])).to.be.equal(treasuryStake.address);

              await checkIndexes(
                staker, // wallet
                tokenId[i], // tokenId
                i, // tokenIdIndex
                2, // allUserTokenIdsLen
                [tokenId[0], tokenId[1]], // allUserTokenIdsExpected
              )
            }

            const actualRewards = await treasuryStake.pendingRewardsAll(staker);
            expect(actualRewards.div(100)).to.be.equal(expectedRewards.div(100));

            const balBefore = await magicToken.balanceOf(staker);
            await treasuryStake.connect(stakerSigner).withdrawAndHarvestAll();
            const balAfter = await magicToken.balanceOf(staker);

            expect(balAfter.sub(balBefore)).to.be.equal(actualRewards);
            expect(await lpToken.ownerOf(tokenId[0])).to.be.equal(staker);
            expect(await lpToken.ownerOf(tokenId[1])).to.be.equal(staker);

            await checkIndexes(
              staker, // wallet
              tokenId[0], // tokenId
              0, // tokenIdIndex
              0, // allUserTokenIdsLen
              [], // allUserTokenIdsExpected
            )

            await checkIndexes(
              staker, // wallet
              tokenId[1], // tokenId
              0, // tokenIdIndex
              0, // allUserTokenIdsLen
              [], // allUserTokenIdsExpected
            )
          }
        });
      })
    })
  })
});

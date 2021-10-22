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
  const tokenId = 1;
  const tokenAmount = 12;

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

    const ERC1155Mintable = await ethers.getContractFactory('ERC1155Mintable')
    lpToken = await ERC1155Mintable.deploy()
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
    depositAmount: any
  ) => {

    allUserDepositIdsLenPrev = ethers.BigNumber.from(allUserDepositIdsLenPrev);
    const lpAmount = await treasuryStake.getLpAmount(tokenId, depositAmount);
    expect(await treasuryStake.totalLpToken()).to.be.equal(totalLpTokenPrev.add(lpAmount));
    const allUserDepositIds = await treasuryStake.getAllUserTokenIds(user);
    expect(allUserDepositIds[allUserDepositIds.length - 1]).to.be.equal(tokenId);
    expect(allUserDepositIds.length).to.be.equal(allUserDepositIdsLenPrev.add(1));
    expect(await treasuryStake.tokenIdIndex(user, tokenId)).to.be.equal(allUserDepositIds.length - 1);

    const userInfo = await treasuryStake.userInfo(user, tokenId);
    expect(userInfo.depositAmount).to.be.equal(depositAmount);
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
      expect(allUserTokenIds[index]).to.be.equal(allUserTokenIdsExpected[index]);
    }
  }

  it('getBoost()', async function () {
    const tests = [
      {tokenId: 39, boost:	1003},
      {tokenId: 46, boost:	821},
      {tokenId: 47, boost:	973},
      {tokenId: 48, boost:	100},
      {tokenId: 49, boost:	204},
      {tokenId: 51, boost:	1015},
      {tokenId: 52, boost:	1015},
      {tokenId: 53, boost:	809},
      {tokenId: 54, boost:	977},
      {tokenId: 68, boost:	752},
      {tokenId: 69, boost:	450},
      {tokenId: 71, boost:	287},
      {tokenId: 72, boost:	774},
      {tokenId: 73, boost:	104},
      {tokenId: 74, boost:	846},
      {tokenId: 75, boost:	762},
      {tokenId: 76, boost:	162},
      {tokenId: 77, boost:	103},
      {tokenId: 79, boost:	101},
      {tokenId: 82, boost:	739},
      {tokenId: 91, boost:	779},
      {tokenId: 92, boost:	103},
      {tokenId: 93, boost:	429},
      {tokenId: 94, boost:	436},
      {tokenId: 95, boost:	1047},
      {tokenId: 96, boost:	105},
      {tokenId: 97, boost:	1052},
      {tokenId: 98, boost:	965},
      {tokenId: 99, boost:	849},
      {tokenId: 100, boost:	710},
      {tokenId: 103, boost:	402},
      {tokenId: 104, boost:	830},
      {tokenId: 105, boost:	896},
      {tokenId: 114, boost:	212},
      {tokenId: 115, boost:	103},
      {tokenId: 116, boost:	772},
      {tokenId: 117, boost:	100},
      {tokenId: 132, boost:	851},
      {tokenId: 133, boost:	103},
      {tokenId: 141, boost:	794},
      {tokenId: 151, boost:	105},
      {tokenId: 152, boost:	798},
      {tokenId: 153, boost:	854},
      {tokenId: 161, boost:	977},
      {tokenId: 162, boost:	791},
      {tokenId: 164, boost:	676}
    ]

    for (let index = 0; index < tests.length; index++) {
      const test = tests[index];
      const amount = ethers.utils.parseUnits('1', 'ether')

      expect(await treasuryStake.getLpAmount(test.tokenId, 1)).to.be.equal(
        amount.add(amount.mul(test.boost).div(100))
      )
    }
  });

  it('deposit()', async function () {
    let totalLpTokenPrev = await treasuryStake.totalLpToken();
    let allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker1)).length;

    await lpToken.functions['mint(address,uint256,uint256)'](staker1, tokenId, tokenAmount);
    expect(await lpToken.balanceOf(staker1, tokenId)).to.be.equal(tokenAmount);
    await lpToken.connect(staker1Signer).setApprovalForAll(treasuryStake.address, true);

    let depositAmount = 5;
    await treasuryStake.connect(staker1Signer).deposit(tokenId, depositAmount);
    let lpAmount = await treasuryStake.getLpAmount(tokenId, depositAmount);

    await checkDeposit(
      tokenId,
      staker1,
      totalLpTokenPrev,
      allUserDepositIdsLenPrev,
      depositAmount
    );

    await checkIndexes(
      staker1, // wallet
      tokenId, // tokenId
      0, // tokenIdIndex
      1, // allUserTokenIdsLen
      [tokenId], // allUserTokenIdsExpected
    )

    totalLpTokenPrev = await treasuryStake.totalLpToken();
    allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker1)).length;

    await treasuryStake.connect(staker1Signer).deposit(tokenId, depositAmount);
    lpAmount = await treasuryStake.getLpAmount(tokenId, depositAmount);

    allUserDepositIdsLenPrev = ethers.BigNumber.from(allUserDepositIdsLenPrev);
    lpAmount = await treasuryStake.getLpAmount(tokenId, depositAmount);
    expect(await treasuryStake.totalLpToken()).to.be.equal(totalLpTokenPrev.add(lpAmount));
    const allUserDepositIds = await treasuryStake.getAllUserTokenIds(staker1);
    expect(allUserDepositIds[allUserDepositIds.length - 1]).to.be.equal(tokenId);
    expect(allUserDepositIds.length).to.be.equal(allUserDepositIdsLenPrev);
    expect(await treasuryStake.tokenIdIndex(staker1, tokenId)).to.be.equal(allUserDepositIds.length - 1);

    const userInfo = await treasuryStake.userInfo(staker1, tokenId);
    expect(userInfo.depositAmount).to.be.equal(depositAmount + depositAmount);
    expect(userInfo.tokenId).to.be.equal(tokenId);
    expect(userInfo.lpAmount).to.be.equal(lpAmount.add(lpAmount));
    expect(userInfo.rewardDebt).to.be.equal((await treasuryStake.accMagicPerShare()).mul(lpAmount).div(await treasuryMine.ONE()));

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

    await lpToken.functions['mint(address,uint256,uint256)'](staker1, tokenId, tokenAmount);
    expect(await lpToken.balanceOf(staker1, tokenId)).to.be.equal(tokenAmount);
    await lpToken.connect(staker1Signer).setApprovalForAll(treasuryStake.address, true);

    const depositAmount = 5;
    await treasuryStake.connect(staker1Signer).deposit(tokenId, depositAmount);
    const lpAmount = await treasuryStake.getLpAmount(tokenId, depositAmount);

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
        [staker1, staker1Signer, 39],
        [staker2, staker2Signer, 77],
        [staker3, staker3Signer, 92],
      ]

      for (let index = 0; index < deposits.length; index++) {
        const staker = deposits[index][0];
        const stakerSigner = deposits[index][1];
        const tokenIdLocal = deposits[index][2];

        const totalLpTokenPrev = await treasuryStake.totalLpToken();
        const allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker)).length;

        await lpToken.functions['mint(address,uint256,uint256)'](staker, tokenIdLocal, tokenAmount);
        expect(await lpToken.balanceOf(staker, tokenIdLocal)).to.be.equal(tokenAmount);
        await lpToken.connect(stakerSigner).setApprovalForAll(treasuryStake.address, true);

        let tx = await treasuryStake.connect(stakerSigner).deposit(tokenIdLocal, tokenAmount);
        tx = await tx.wait();
        const lpAmount = await treasuryStake.getLpAmount(tokenIdLocal, tokenAmount);

        await checkDeposit(
          tokenIdLocal,
          staker,
          totalLpTokenPrev,
          allUserDepositIdsLenPrev,
          tokenAmount
        );

        await checkIndexes(
          staker, // wallet
          tokenId, // tokenId
          0, // tokenIdIndex
          1, // allUserTokenIdsLen
          [tokenIdLocal], // allUserTokenIdsExpected
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

        await treasuryStake.connect(stakerSigner).withdrawPosition(tokenId, tokenAmount);

        const userInfo = await treasuryStake.userInfo(staker, tokenId);
        expect(await treasuryStake.totalLpToken()).to.be.equal(totalLpTokenPrev.sub(userInfoPrev.lpAmount));
        expect(userInfo.tokenId).to.be.equal(tokenId);
        expect(userInfo.depositAmount).to.be.equal(0);
        expect(userInfo.lpAmount).to.be.equal(0);
        expect(userInfo.rewardDebt).to.be.equal(0);
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

        await treasuryStake.connect(stakerSigner).withdrawPosition(tokenId, tokenAmount / 2);

        const userInfo = await treasuryStake.userInfo(staker, tokenId);
        expect(await treasuryStake.totalLpToken()).to.be.equal(totalLpTokenPrev.sub(userInfoPrev.lpAmount.div(2)));
        expect(userInfo.tokenId).to.be.equal(tokenId);
        expect(userInfo.depositAmount).to.be.equal(userInfoPrev.depositAmount.div(2));
        expect(userInfo.lpAmount.sub(userInfoPrev.lpAmount.div(2)) < 2).to.be.true;
      }
    });

    it('notifyRewards()', async function () {
      expect(await treasuryStake.totalLpToken()).to.be.equal('181080000000000000000');
      expect(await treasuryStake.accMagicPerShare()).to.be.equal(0);
      expect(await treasuryStake.undistributedRewards()).to.be.equal(0);

      const rewards = ethers.utils.parseUnits('100', 'ether');
      await magicToken.mint(deployer, rewards);
      await magicToken.approve(treasuryStake.address, rewards);
      await treasuryStake.notifyRewards(rewards);

      const expectedRewards = [
        '73094764744864148359',
        '13452617627567925763',
        '13452617627567925763'
      ]

      for (let index = 0; index < deposits.length; index++) {
        const staker = deposits[index][0];
        const stakerSigner = deposits[index][1];
        const tokenId = deposits[index][2];

        expect(await treasuryStake.pendingRewardsPosition(staker, tokenId)).to.be.equal(expectedRewards[index])
        await treasuryStake.connect(stakerSigner).harvestPosition(tokenId);

        expect(await magicToken.balanceOf(staker)).to.be.equal(expectedRewards[index])
      }
    });

    describe('with second wave of deposits', function () {
      let secondDeposits: any;

      beforeEach(async function () {
        secondDeposits = [
          [staker1, staker1Signer, 3],
          [staker2, staker2Signer, 4],
          [staker3, staker3Signer, 5],
        ]

        for (let index = 0; index < secondDeposits.length; index++) {
          const staker = secondDeposits[index][0];
          const stakerSigner = secondDeposits[index][1];
          const tokenIdLocal = secondDeposits[index][2];

          const totalLpTokenPrev = await treasuryStake.totalLpToken();
          const allUserDepositIdsLenPrev = (await treasuryStake.getAllUserTokenIds(staker)).length;

          await lpToken.functions['mint(address,uint256,uint256)'](staker, tokenIdLocal, tokenAmount);
          expect(await lpToken.balanceOf(staker, tokenIdLocal)).to.be.equal(tokenAmount);
          await lpToken.connect(stakerSigner).setApprovalForAll(treasuryStake.address, true);

          let tx = await treasuryStake.connect(stakerSigner).deposit(tokenIdLocal, tokenAmount);
          tx = await tx.wait();
          const lpAmount = await treasuryStake.getLpAmount(tokenIdLocal, tokenAmount);


          await checkDeposit(
            tokenIdLocal,
            staker,
            totalLpTokenPrev,
            allUserDepositIdsLenPrev,
            tokenAmount
          );

          await checkIndexes(
            staker, // wallet
            tokenIdLocal, // tokenId
            1, // tokenIdIndex
            2, // allUserTokenIdsLen
            [deposits[index][2], tokenIdLocal], // allUserTokenIdsExpected
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
            expect(userInfo.tokenId).to.be.equal(tokenId[i]);
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
              expect(actualRewards.div(1000)).to.be.equal(expectedRewards.div(1000));

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
            expect(actualRewards.div(1000)).to.be.equal(expectedRewards.div(1000));

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
              expect(await lpToken.balanceOf(treasuryStake.address, tokenId[i])).to.be.equal(tokenAmount);
              expect(await lpToken.balanceOf(staker, tokenId[i])).to.be.equal(0);
              await treasuryStake.connect(stakerSigner).withdrawAndHarvestPosition(tokenId[i], tokenAmount);
              expect(await lpToken.balanceOf(treasuryStake.address, tokenId[i])).to.be.equal(0);
              expect(await lpToken.balanceOf(staker, tokenId[i])).to.be.equal(tokenAmount);
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

              expect(await lpToken.balanceOf(treasuryStake.address, tokenId[i])).to.be.equal(tokenAmount);

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
            expect(await lpToken.balanceOf(staker, tokenId[0])).to.be.equal(tokenAmount);
            expect(await lpToken.balanceOf(staker, tokenId[1])).to.be.equal(tokenAmount);

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

import {
  advanceTimeAndBlock,
  ERC20__factory,
  getBlockTimestamp,
  MAX_UINT_AMOUNT,
  waitForTx,
} from "@aave/deploy-v3";
import { parseEther } from "@ethersproject/units";
import Bluebird from "bluebird";
import { BigNumber } from "ethers";
import hre from "hardhat";

import { ATokenMock__factory } from "../../types";
import { makeSuite } from "../helpers/make-suite";
import {
  assetDataComparator,
  getRewards,
  getRewardsData,
} from "./helpers/RewardsDistributor/data-helpers/asset-data";
import { getUserIndex } from "./helpers/RewardsDistributor/data-helpers/asset-user-data";

const { expect } = require("chai");

type ScenarioAction = {
  caseName: string;
  emissionsPerSecond: string[];
  zeroBalance: boolean[];
  toStake?: boolean;
};

const getRewardsBalanceScenarios: ScenarioAction[] = [
  {
    caseName: "Accrued rewards are 0",
    emissionsPerSecond: ["0", "0", "0"],
    zeroBalance: [false, false, false],
  },
  {
    caseName: "Accrued rewards are not 0",
    emissionsPerSecond: ["2432424", "4432424", "1234"],
    zeroBalance: [false, false, false],
  },
  {
    caseName: "Some rewards are not 0",
    emissionsPerSecond: ["2432424", "0", "1234"],
    zeroBalance: [false, false, false],
  },
  {
    caseName: "Some rewards are not 0",
    emissionsPerSecond: ["0", "2432424", "1234"],
    zeroBalance: [false, false, false],
  },
  {
    caseName: "Some user balances are not 0",
    emissionsPerSecond: ["13412", "2432424", "0"],
    zeroBalance: [false, true, true],
  },
  {
    caseName: "Some user balances are not 0",
    emissionsPerSecond: ["13412", "2432424", "0"],
    zeroBalance: [true, false, true],
  },
  {
    caseName: "Should withdraw to another user",
    emissionsPerSecond: ["2314", "3331", "421512"],
    zeroBalance: [false, false, false],
  },
  {
    caseName: "Should withdraw to another user",
    emissionsPerSecond: ["2314", "3331", "421512"],
    zeroBalance: [false, false, false],
  },
  {
    caseName: "Should not claim due emissions are zero",
    emissionsPerSecond: ["0", "0", "0"],
    zeroBalance: [false, false, false],
  },
];

makeSuite("Incentives Controller V2 claimRewards to self tests", (testEnv) => {
  before(async () => {
    const { rewardTokens, rewardsVault, pullRewardsStrategy } = testEnv;
    const rewards = rewardTokens.slice(0, 3);

    await Bluebird.each(rewards, async (reward, index) => {
      await reward
        .connect(rewardsVault.signer)
        ["mint(uint256)"](parseEther("1000000000"));
      await reward
        .connect(rewardsVault.signer)
        .approve(pullRewardsStrategy.address, MAX_UINT_AMOUNT);
    });
  });

  for (const {
    caseName,
    emissionsPerSecond,
    zeroBalance,
  } of getRewardsBalanceScenarios) {
    it(caseName, async () => {
      const { timestamp } = await hre.ethers.provider.getBlock("latest");
      const timePerTest = 31536000;
      const distributionEnd =
        timestamp + timePerTest * getRewardsBalanceScenarios.length;
      await advanceTimeAndBlock(timePerTest);
      const {
        rewardsController,
        aDaiMockV2,
        aAaveMockV2,
        aWethMockV2,
        pullRewardsStrategy,
        rewardTokens,
        deployer,
      } = testEnv;

      const userAddress = await rewardsController.signer.getAddress();

      const assets = [aDaiMockV2, aAaveMockV2, aWethMockV2].map(
        ({ address }) => address,
      );
      const stakedByUser = assets.map((_, index) =>
        zeroBalance[index]
          ? BigNumber.from("0")
          : BigNumber.from(parseEther("20000")).mul(caseName.length).mul(index),
      );
      const totalSupply = assets.map((_, index) =>
        BigNumber.from(parseEther("100000")).mul(caseName.length).mul(index),
      );
      const rewards = rewardTokens.slice(0, 3).map(({ address }) => address);

      await Bluebird.each(assets, async (asset, index) => {
        await ATokenMock__factory.connect(
          asset,
          deployer.signer,
        ).setUserBalanceAndSupply(stakedByUser[index], totalSupply[index]);
      });

      // update emissionPerSecond in advance to not affect user calculations

      await waitForTx(
        await rewardsController.configureAssets(
          emissionsPerSecond.map((emissionPerSecond, index) => ({
            asset: assets[index],
            reward: rewards[index],
            rewardOracle: testEnv.oracle.address,
            emissionPerSecond,
            distributionEnd,
            totalSupply: totalSupply[index],
            transferStrategy: pullRewardsStrategy.address,
          })),
        ),
      );

      const destinationAddress = userAddress;

      const destinationAddressBalanceBefore = await Bluebird.map(
        rewards,
        async (reward) =>
          await ERC20__factory.connect(reward, deployer.signer).balanceOf(
            destinationAddress,
          ),
      );

      await Bluebird.each(assets, async (asset, index) => {
        await ATokenMock__factory.connect(
          asset,
          deployer.signer,
        ).handleActionOnAic(
          userAddress,
          totalSupply[index],
          stakedByUser[index],
        );
      });

      const unclaimedRewardsBefore = await Bluebird.map(rewards, (reward) =>
        rewardsController.getUserRewards(assets, userAddress, reward),
      );

      const unclaimedRewardsStorageBefore = await Bluebird.map(
        rewards,
        (reward) =>
          rewardsController.getUserAccruedRewards(userAddress, reward),
      );

      const userIndexesBefore = await Bluebird.map(
        rewards,
        async (reward, index) =>
          await getUserIndex(
            rewardsController,
            userAddress,
            assets[index],
            reward,
          ),
      );

      const assetDataBefore = await Bluebird.map(
        rewards,
        async (reward, index) =>
          (
            await getRewardsData(rewardsController, [assets[index]], [reward])
          )[0],
      );

      const action = await rewardsController.claimAllRewardsToSelf(assets);

      const claimRewardsReceipt = await waitForTx(action);

      const actionBlockTimestamp = await getBlockTimestamp(
        claimRewardsReceipt.blockNumber,
      );

      const userIndexesAfter = await Bluebird.map(
        rewards,
        async (reward, index) =>
          await getUserIndex(
            rewardsController,
            userAddress,
            assets[index],
            reward,
          ),
      );

      const assetDataAfter = await Bluebird.map(
        rewards,
        async (reward, index) =>
          (
            await getRewardsData(rewardsController, [assets[index]], [reward])
          )[0],
      );

      const unclaimedRewardsStorageAfter = await Bluebird.map(
        rewards,
        (reward) =>
          rewardsController.getUserAccruedRewards(userAddress, reward),
      );

      const destinationAddressBalanceAfter = await Bluebird.map(
        rewards,
        async (reward) =>
          await ERC20__factory.connect(reward, deployer.signer).balanceOf(
            destinationAddress,
          ),
      );

      const claimedAmounts = await Bluebird.map(
        destinationAddressBalanceAfter,
        (balance, index) => balance.sub(destinationAddressBalanceBefore[index]),
      );

      await aDaiMockV2.cleanUserState();

      const expectedAccruedRewards = await Bluebird.map(rewards, (_, index) =>
        getRewards(
          stakedByUser[index],
          userIndexesAfter[index],
          userIndexesBefore[index],
        ).toString(),
      );
      await Bluebird.each(assets, async (asset, i) => {
        await assetDataComparator(
          { underlyingAsset: asset, totalSupply: totalSupply[i] },
          assetDataBefore[i],
          assetDataAfter[i],
          actionBlockTimestamp,
          distributionEnd,
          {},
        );

        expect(
          userIndexesAfter[i].toString(),
          "user index are not correctly updated",
        ).to.be.equal(
          assetDataAfter[i].index.toString(),
          "user index are not correctly updated",
        );

        if (!assetDataAfter[i].index.eq(assetDataBefore[i].index)) {
          await expect(action)
            .to.emit(rewardsController, "Accrued")
            .withArgs(
              assetDataAfter[i].underlyingAsset,
              rewards[i],
              userAddress,
              assetDataAfter[i].index,
              assetDataAfter[i].index,
              expectedAccruedRewards[i],
            );
        }

        const expectedClaimedAmount: BigNumber = unclaimedRewardsStorageBefore[
          i
        ].add(expectedAccruedRewards[i]);
        expect(unclaimedRewardsStorageAfter[i].toString()).to.be.equal(
          "0",
          "unclaimed amount after should go to 0",
        );

        expect(claimedAmounts[i].toString()).to.be.equal(
          expectedClaimedAmount.toString(),
          "claimed amount are wrong",
        );

        if (expectedClaimedAmount.gt(0)) {
          await expect(action)
            .to.emit(rewardsController, "RewardsClaimed")
            .withArgs(
              userAddress,
              rewards[i],
              destinationAddress,
              userAddress,
              expectedClaimedAmount,
            );
        }
      });
    });
  }
});

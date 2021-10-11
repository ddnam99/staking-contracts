import hre from "hardhat";
import { Contract, Signer } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";

describe("Staking", function () {
  let ownerStaking: Contract;
  let ownerToken: Contract;
  let StakingContract: Contract;
  let TokenContract: Contract;

  let accounts: Signer[];

  const startTestTime = Math.round(Date.now() / 1000);
  const decimalMultiplier = BigNumber.from(10).pow(18);

  before(async function () {
    const StakingFactory = await hre.ethers.getContractFactory("StakingMock");
    const TokenFactory = await hre.ethers.getContractFactory("Token");

    StakingContract = await StakingFactory.deploy();
    TokenContract = await TokenFactory.deploy();

    await StakingContract.deployed();
    await TokenContract.deployed();

    accounts = await hre.ethers.getSigners();

    ownerStaking = await hre.ethers.getContractAt("StakingMock", StakingContract.address, StakingContract.signer);
    ownerToken = await hre.ethers.getContractAt("Token", TokenContract.address, TokenContract.signer);
  });

  describe("Setup", function () {
    it("Should block timestamp must be not equal 0", async () => {
      const user1 = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);

      const blockTimestamp: BigNumber = await user1.blockTimestamp();

      expect(blockTimestamp).to.not.equal(BigNumber.from(0));
    });

    it("Should account deploy contract has role admin", async () => {
      const DEFAULT_ADMIN_ROLE = await ownerStaking.DEFAULT_ADMIN_ROLE();
      const isAdmin = await ownerStaking.hasRole(DEFAULT_ADMIN_ROLE, ownerStaking.signer.getAddress());

      expect(isAdmin).equal(true);
    });

    it("Should mint 10000 token for accounts", async () => {
      await Promise.all(
        accounts.map(async acc => {
          return await ownerToken.mint(await acc.getAddress(), BigNumber.from(10000).mul(decimalMultiplier));
        }),
      );

      const balanceOfUser5: BigNumber = await ownerToken.balanceOf(await accounts[5].getAddress());
      expect(balanceOfUser5.toHexString()).equal(BigNumber.from(10000).mul(decimalMultiplier).toHexString());
    });

    it("Should approve 10000 token for StakingContract", async () => {
      await Promise.all(
        accounts.map(async acc => {
          const user = await hre.ethers.getContractAt("Token", TokenContract.address, acc);
          return await user.approve(StakingContract.address, BigNumber.from(10000).mul(decimalMultiplier));
        }),
      );

      const allowance: BigNumber = await TokenContract.allowance(
        await accounts[5].getAddress(),
        StakingContract.address,
      );
      expect(allowance.toHexString()).equal(BigNumber.from(10000).mul(decimalMultiplier).toHexString());
    });
  });

  describe("Add stake event", function () {
    it("Should add stake event success", async () => {
      await ownerStaking.createEvent(
        startTestTime + 5,
        startTestTime + 24 * 60 * 60,
        TokenContract.address,
        BigNumber.from(1).mul(decimalMultiplier),
        BigNumber.from(1000).mul(decimalMultiplier),
        30,
        TokenContract.address,
        20,
      );

      const stakeEvent = await ownerStaking.getStakeEvent(0);
      const stakeEvents = await ownerStaking.getAllStakeEvents();

      expect(stakeEvent.isActive && stakeEvents.length == 1).equal(true);
    });
  });

  describe("Close stake event", function () {
    it("Setup stake event inactive", async () => {
      await ownerStaking.createEvent(
        startTestTime + 5,
        startTestTime + 24 * 60 * 60,
        TokenContract.address,
        BigNumber.from(1).mul(decimalMultiplier),
        BigNumber.from(1000).mul(decimalMultiplier),
        30,
        TokenContract.address,
        20,
      );

      await ownerStaking.setBlockTimestamp(startTestTime + 100);
      await ownerStaking.closeStakeEvent(1);

      const stakeEvent = await ownerStaking.getStakeEvent(1);

      expect(stakeEvent.isActive).equal(false);
    });

    it("Should not in active stake token list", async () => {
      const activeStakeEvents = await ownerStaking.getActiveStakeEvents();

      expect(activeStakeEvents.length).equal(1);
    });
  });

  describe("User stake token", function () {
    it("Should stake failed when stake event closed", async () => {
      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);

      try {
        await user.stake(1, BigNumber.from(200).mul(decimalMultiplier));
        expect(true).equal(false);
      } catch (err: any) {
        expect(err.message.includes("Stake event closed")).equal(true);
      }
    });

    it("Should stake failed when stake event over end time", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 2 * 24 * 60 * 60);

      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);

      try {
        await user.stake(1, BigNumber.from(200).mul(decimalMultiplier));
        expect(true).equal(false);
      } catch (err: any) {
        expect(err.message.includes("Stake event closed")).equal(true);
      }
    });

    it("Should stake success when event is open", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 100);
      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);
      const userAddress = await accounts[1].getAddress();

      await user.stake(0, BigNumber.from(200).mul(decimalMultiplier));

      const stakeInfo = await user.getStakeInfo(0, userAddress);

      expect(stakeInfo.amount.toHexString()).equal(BigNumber.from(200).mul(decimalMultiplier).toHexString());
    });
  });

  describe("Reward", function () {
    it("Should return 0 reward when stake event not close", async () => {
      const userAddress = await accounts[1].getAddress();

      const rewardClaimable: BigNumber = await ownerStaking.getRewardClaimable(0, userAddress);

      expect(rewardClaimable.toHexString()).equal(BigNumber.from(0).toHexString());
    });

    it("Should return reward when stake event close", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 10 * 24 * 60 * 60 + 100);
      const userAddress = await accounts[1].getAddress();

      const rewardClaimable: BigNumber = await ownerStaking.getRewardClaimable(0, userAddress);
      const stakeInfo = await ownerStaking.getStakeInfo(0, userAddress);
      const stakeEvent = await ownerStaking.getStakeEvent(0);

      const reward = stakeInfo.amount.mul(10).mul(stakeEvent.rewardPercent).div(stakeEvent.cliff.mul(100));

      expect(rewardClaimable.toHexString()).equal(reward.toHexString());
    });

    it("Should return all reward when stake event over cliff", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 30 * 24 * 60 * 60 + 100);
      const userAddress = await accounts[1].getAddress();

      const rewardClaimable: BigNumber = await ownerStaking.getRewardClaimable(0, userAddress);
      const stakeInfo = await ownerStaking.getStakeInfo(0, userAddress);
      const stakeEvent = await ownerStaking.getStakeEvent(0);

      const reward = stakeInfo.amount.mul(stakeEvent.rewardPercent).div(100);

      expect(rewardClaimable.toHexString()).equal(reward.toHexString());
    });

    it("Should balance of user is equal old balance + reward", async () => {
      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);
      const userAddress = await accounts[1].getAddress();

      const stakeInfo = await ownerStaking.getStakeInfo(0, userAddress);

      const rewardClaimable: BigNumber = await ownerStaking.getRewardClaimable(0, userAddress);
      const oldBalanceOfUser: BigNumber = await ownerToken.balanceOf(userAddress);

      await user.withdraw(0);

      const currentBalanceOfUser: BigNumber = await ownerToken.balanceOf(userAddress);

      expect(currentBalanceOfUser.toHexString()).equal(
        oldBalanceOfUser.add(stakeInfo.amount).add(rewardClaimable).toHexString(),
      );
    });
  });
});

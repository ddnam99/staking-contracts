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

    it("Should mint 100000000 token for accounts", async () => {
      await Promise.all(
        accounts.map(async acc => {
          return await ownerToken.mint(await acc.getAddress(), BigNumber.from(100000000).mul(decimalMultiplier));
        }),
      );

      await ownerToken.mint(await ownerStaking.signer.getAddress(), BigNumber.from(100000000).mul(decimalMultiplier));

      const balanceOfUser5: BigNumber = await ownerToken.balanceOf(await accounts[5].getAddress());
      expect(balanceOfUser5.toHexString()).equal(BigNumber.from(100000000).mul(decimalMultiplier).toHexString());
    });

    it("Should approve 100000000 token for StakingContract", async () => {
      await Promise.all(
        accounts.map(async acc => {
          const user = await hre.ethers.getContractAt("Token", TokenContract.address, acc);
          return await user.approve(StakingContract.address, BigNumber.from(100000000).mul(decimalMultiplier));
        }),
      );

      const owStaking = await hre.ethers.getContractAt("Token", TokenContract.address, ownerStaking.signer);
      await owStaking.approve(StakingContract.address, BigNumber.from(100000000).mul(decimalMultiplier));

      const allowance: BigNumber = await TokenContract.allowance(
        await accounts[5].getAddress(),
        StakingContract.address,
      );
      expect(allowance.toHexString()).equal(BigNumber.from(100000000).mul(decimalMultiplier).toHexString());
    });
  });

  describe("Add pool", function () {
    it("Should add pool success", async () => {
      await ownerStaking.createPool(
        startTestTime + 5,
        TokenContract.address,
        TokenContract.address,
        BigNumber.from(100).mul(decimalMultiplier),
        BigNumber.from(10000).mul(decimalMultiplier),
        BigNumber.from(1000000).mul(decimalMultiplier),
        90,
        1,
        20,
        100,
        true,
        BigNumber.from(2000).mul(decimalMultiplier),
      );

      const pool = await ownerStaking.getDetailPool(0);
      const pools = await ownerStaking.getAllPools();

      expect(pool.isActive && pools.length == 1).equal(true);
    });
  });

  describe("Close pool", function () {
    it("Setup pool inactive", async () => {
      await ownerStaking.createPool(
        startTestTime + 5,
        TokenContract.address,
        TokenContract.address,
        BigNumber.from(100).mul(decimalMultiplier),
        BigNumber.from(10000).mul(decimalMultiplier),
        BigNumber.from(1000000).mul(decimalMultiplier),
        90,
        1,
        20,
        100,
        true,
        BigNumber.from(2000).mul(decimalMultiplier),
      );

      await ownerStaking.setBlockTimestamp(startTestTime + 100);
      await ownerStaking.closePool(1);

      const pool = await ownerStaking.getDetailPool(1);

      expect(pool.isActive).equal(false);
    });

    it("Should not in active stake token list", async () => {
      const activePools = await ownerStaking.getActivePools();

      expect(activePools.length).equal(1);
    });
  });

  describe("User stake token", function () {
    it("Should stake failed when pool closed", async () => {
      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);

      try {
        await user.stake(1, BigNumber.from(200).mul(decimalMultiplier));
        expect(true).equal(false);
      } catch (err) {
        // @ts-ignore
        expect(err?.message?.includes("Pool closed")).equal(true);
      }
    });

    it("Should stake failed when pool over end time", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 2 * 24 * 60 * 60);

      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);

      try {
        await user.stake(1, BigNumber.from(200).mul(decimalMultiplier));
        expect(true).equal(false);
      } catch (err) {
        // @ts-ignore
        expect(err.message.includes("Pool closed")).equal(true);
      }
    });

    it("Should stake success when pool is open", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 100);
      const user1 = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);
      const user2 = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[2]);
      const user3 = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[3]);
      const user4 = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[4]);
      const userAddress1 = await accounts[1].getAddress();

      await user1.stake(0, BigNumber.from(2000).mul(decimalMultiplier));
      await user2.stake(0, BigNumber.from(200).mul(decimalMultiplier));
      await user3.stake(0, BigNumber.from(200).mul(decimalMultiplier));
      await user4.stake(0, BigNumber.from(2000).mul(decimalMultiplier));

      const stakeInfo = await user1.getStakeInfo(0, userAddress1);

      expect(stakeInfo.amount.toHexString()).equal(BigNumber.from(2000).mul(decimalMultiplier).toHexString());
    });

    it("Should in white list after stake qualified", async () => {
      const userAddress = await accounts[1].getAddress();

      const isWL = await ownerStaking.checkWhiteList(0, userAddress);

      expect(isWL).equal(true);
    });

    it("Should not in white list after stake not qualified", async () => {
      const userAddress = await accounts[2].getAddress();

      const isWL = await ownerStaking.checkWhiteList(0, userAddress);

      expect(isWL).equal(false);
    });

    it("Should not in white list after un stake", async () => {
      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[4]);
      const userAddress = await accounts[4].getAddress();

      await user.unStake(0);
      const isWL = await ownerStaking.checkWhiteList(0, userAddress);

      expect(isWL).equal(false);
    });
  });

  describe("Reward", function () {
    it("Should return 0 reward before value date", async () => {
      const userAddress = await accounts[2].getAddress();

      const rewardClaimable: BigNumber = await ownerStaking.getRewardClaimable(0, userAddress);

      expect(rewardClaimable.toHexString()).equal(BigNumber.from(0).toHexString());
    });

    it("Should return error when withdraw not over pool duration", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 10 * 24 * 60 * 60 + 100);
      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[3]);

      try {
        await user.withdraw(0);
        expect(true).equal(false);
      } catch (err) {
        // @ts-ignore
        expect(err.message.includes("Cannot withdraw before redemption period")).equal(true);
      }
    });

    it("Should return all reward when pool over duration", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 100 * 24 * 60 * 60 + 100);
      const userAddress = await accounts[1].getAddress();

      const rewardClaimable: BigNumber = await ownerStaking.getRewardClaimable(0, userAddress);
      const stakeInfo = await ownerStaking.getStakeInfo(0, userAddress);
      const pool = await ownerStaking.getDetailPool(0);

      const reward = stakeInfo.amount.mul(pool.apr).mul(pool.duration).div(365).div(pool.denominatorAPR);

      expect(rewardClaimable.toHexString()).equal(reward.toHexString());
    });

    it("Should return error when withdraw in redemption period", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 91 * 24 * 60 * 60 + 8 * 60 * 60);

      const user = await hre.ethers.getContractAt("StakingMock", StakingContract.address, accounts[1]);

      try {
        await user.withdraw(0);
        expect(true).equal(false);
      } catch (err) {
        // @ts-ignore
        expect(err.message.includes("Cannot withdraw before redemption period")).equal(true);
      }
    });

    it("Should balance of user is equal old balance + reward", async () => {
      await ownerStaking.setBlockTimestamp(startTestTime + 100 * 24 * 60 * 60 + 100);

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

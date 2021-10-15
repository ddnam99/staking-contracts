import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { resolve } from "path";
import { config as dotenvConfig } from "dotenv";
import { BigNumber } from "@ethersproject/bignumber";

dotenvConfig({ path: resolve(__dirname, "../../.env") });

const multiSigAccount: string | undefined = process.env.MULTI_SIG_ACCOUNT;
if (!multiSigAccount) {
  throw new Error("Please set your MULTI_SIG_ACCOUNT in a .env file");
}

const vrfAddress: string | undefined = process.env.VRF_ADDRESS;
if (!vrfAddress) {
  throw new Error("Please set your VRF_ADDRESS in a .env file");
}

const linkAddress: string | undefined = process.env.LINK_ADDRESS;
if (!linkAddress) {
  throw new Error("Please set your LINK_ADDRESS in a .env file");
}

const keyHash: string | undefined = process.env.KEY_HASH;
if (!keyHash) {
  throw new Error("Please set your KEY_HASH in a .env file");
}

const fee: BigNumber = BigNumber.from(Number(process.env.FEE) * 10).mul(BigNumber.from(10).mul(17));
if (!fee) {
  throw new Error("Please set your FEE in a .env file");
}

task("deploy:staking-chainlink")
  .addFlag("verify", "Verify contracts at Etherscan")
  .setAction(async ({}, hre: HardhatRuntimeEnvironment) => {
    const Staking = await hre.ethers.getContractFactory("StakingChainLink");

    // @ts-ignore
    const token = await Staking.deploy(multiSigAccount, vrfAddress, linkAddress, keyHash, fee);
    await token.deployed();
    console.log("token deployed to: ", token.address);

    // We need to wait a little bit to verify the contract after deployment
    await delay(30000);
    await hre.run("verify:verify", {
      address: token.address,
      constructorArguments: [multiSigAccount, vrfAddress, linkAddress, keyHash, fee],
      libraries: {},
    });
  });

function delay(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

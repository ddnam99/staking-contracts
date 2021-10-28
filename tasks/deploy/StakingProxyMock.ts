import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

task("deploy:staking-proxy-mock")
  .addFlag("verify", "Verify contracts at Etherscan")
  .setAction(async ({}, hre: HardhatRuntimeEnvironment) => {
    const tokenFactory = await hre.ethers.getContractFactory("StakingProxyMock");

    const ownerAddress = (await hre.ethers.getSigners())[0].address;

    const proxy = await hre.upgrades.deployProxy(tokenFactory, [ownerAddress]);
    await proxy.deployed();
    console.log("Proxy deployed to:", proxy.address);
  });

function delay(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

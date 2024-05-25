async function main() {
    const { ethers, upgrades } = require("hardhat");
  
    const StakingContract = await ethers.getContractFactory("StakingContract");
    console.log("Deploying StakingContract...");
    const stakingContract = await upgrades.deployProxy(StakingContract, ["0x4232ea0aF92754Ad61c7B75aF9Ed3e2b7E842fFf", "0xef1a07cd949087810d14fb80b53da214ef8f9a3d"], { initializer: "initialize" });
    await stakingContract.deployed();
    console.log("StakingContract deployed to:", stakingContract.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
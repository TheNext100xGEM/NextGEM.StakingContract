const hre = require("hardhat");

async function main() {
  // We get the contract to deploy
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);

  const balance = await deployer.getBalance();
  console.log("Account balance:", hre.ethers.utils.formatEther(balance.toString()));

  const StakingContract = await hre.ethers.getContractFactory("StakingContract");
  
  // Replace these with the actual addresses and values
  const subscriptionAddress = "0x4dcD2a5E68638E0b64766f59C15C02ca11411D98";
  const stakingTokenAddress = "0xFBE44caE91d7Df8382208fCdc1fE80E40FBc7e9a";
  const averageBlockTime = 13; // Assuming an average block time of 13 seconds
  
  const stakingContract = await StakingContract.deploy(subscriptionAddress, stakingTokenAddress, averageBlockTime);

  await stakingContract.deployed();

  console.log("StakingContract deployed to:", stakingContract.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
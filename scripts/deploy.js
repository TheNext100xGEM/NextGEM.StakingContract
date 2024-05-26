// scripts/deploy.js

const hre = require("hardhat");

async function main() {
  // We get the contract to deploy
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);

  const balance = await deployer.getBalance();
  console.log("Account balance:", hre.ethers.utils.formatEther(balance.toString()));

  const StakingContract = await hre.ethers.getContractFactory("StakingContract");
  
  // Replace these with the actual addresses
  const subscriptionAddress = "0xYourSubscriptionContractAddress";
  const stakingTokenAddress = "0xYourStakingTokenAddress";
  
  const stakingContract = await StakingContract.deploy(subscriptionAddress, stakingTokenAddress);

  await stakingContract.deployed();

  console.log("StakingContract deployed to:", stakingContract.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

async function main() {
    const [deployer] = await ethers.getSigners();
  
    console.log("Deploying contracts with the account:", deployer.address);
  
    const GemAiStakingService = await ethers.getContractFactory("GemAiStakingService");
    const deployment = await GemAiStakingService.deploy(); //GEMAI CONTRACT

  
    console.log("Contract address:", deployment.address);
}
  
main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});
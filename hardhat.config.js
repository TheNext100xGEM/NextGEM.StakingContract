require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-ethers");

module.exports = {
  solidity: "0.8.20",
  networks: {
    mainnet: {
      url: `https://sepolia.infura.io/v3/5982800e8b2940c689c2b7335f104c61`,
      accounts: [``]
    }
  }
};
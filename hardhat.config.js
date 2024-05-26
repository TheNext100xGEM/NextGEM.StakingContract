require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-ethers");

module.exports = {
  solidity: "0.8.20",
  networks: {
    mainnet: {
      url: `https://sepolia.infura.io/v3/5982800e8b2940c689c2b7335f104c61`,
      accounts: [`0x6596c4628d692bf04df6f9de254090db6d7f80f80ea55bd5f167f13d844e7f04`]
    }
  }
};
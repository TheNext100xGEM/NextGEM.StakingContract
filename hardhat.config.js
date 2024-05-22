require("@nomiclabs/hardhat-waffle");

module.exports = {
  solidity: "0.8.0",
  networks: {
    mainnet: {
      url: `https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID`,
      accounts: [`0x${YOUR_MAINNET_PRIVATE_KEY}`]
    }
  }
};
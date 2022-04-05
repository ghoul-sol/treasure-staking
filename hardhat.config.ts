import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import 'dotenv/config';
import {HardhatUserConfig} from 'hardhat/types';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import 'hardhat-gas-reporter';
import 'solidity-coverage';

const privateKey = process.env.DEV_PRIVATE_KEY || "a35028be607c31f34f141f1a565b66ff519399d6ec05d16f565c2b7b3a9b90a8"; // address: 0xa60C5868cE00D2a011144b741cFeFB368C19e057
const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        enabled: process.env.FORKING === "true",
        url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        // url: `https://arbitrum-mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
        blockNumber: 7365993
      },
      live: false,
      saveDeployments: true,
      tags: ["test", "local"],
      chainId : 1337,
      deploy: ["deploy/arbitrum"],
    },
    localhost: {
      url: "http://localhost:8545",
      chainId : 1337,
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [`${privateKey}`],
      chainId: 4,
      live: true,
      saveDeployments: true,
      tags: ["staging"]
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [`${privateKey}`],
      chainId: 42,
      live: true,
      saveDeployments: true,
      tags: ["staging"]
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [`${privateKey}`],
      chainId: 1,
      live: true,
      saveDeployments: true,
      gasMultiplier: 2
    },
    polygon: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [`${privateKey}`],
      chainId: 137,
      live: true,
      saveDeployments: true,
      gasMultiplier: 2,
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: [`${privateKey}`],
      chainId: 42161,
      live: true,
      saveDeployments: true,
      gasMultiplier: 2,
      deploy: ["deploy/arbitrum"],
    },
    arbitrumRinkeby: {
      url: "https://rinkeby.arbitrum.io/rpc",
      accounts: [`${privateKey}`],
      chainId: 421611,
      live: true,
      saveDeployments: true,
      gasMultiplier: 2,
      deploy: ["deploy/arbitrumRinkeby"],
    },
    arbitrumStaging: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: [`${privateKey}`],
      chainId: 42161,
      live: true,
      saveDeployments: true,
      gasMultiplier: 2,
      deploy: ["deploy/arbitrumStaging"],
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.11",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
    ],
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  namedAccounts: {
    deployer: 0,
    staker1: 1,
    staker2: 2,
    staker3: 3,
    hacker: 4
  },
  mocha: {
    timeout: 1560000,
  },
  gasReporter: {
    currency: 'USD',
    enabled: false,
  },
  paths: {
    artifacts: "artifacts",
    cache: "cache",
    deploy: "deploy",
    deployments: "deployments",
    imports: "imports",
    sources: "contracts",
    tests: "test",
  }
};

export default config;

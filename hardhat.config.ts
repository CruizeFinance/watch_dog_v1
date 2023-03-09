import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
import "hardhat-tracer";
import "hardhat-deploy";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-storage-layout";
import "hardhat-storage-layout-changes";
import { HttpNetworkUserConfig } from "hardhat/types";
dotenv.config({ path: __dirname + "/.env" });

const DEFAULT_MNEMONIC: string = process.env.MNEMONIC || "";

const sharedNetworkConfig: HttpNetworkUserConfig = {
  live: true,
  saveDeployments: true,
  timeout: 8000000,
  gasPrice: "auto",
};

if (process.env.PRIVATE_KEY) {
  sharedNetworkConfig.accounts = [process.env.PRIVATE_KEY];
} else {
  sharedNetworkConfig.accounts = {
    mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
  };
}

export default {
  namedAccounts: {
    deployer: 1,
  },
  paths: {
    tests: "./test",
    cache: "./cache",
    deploy: "./src/deploy",
    sources: "./contracts",
    deployments: "./deployments",
    artifacts: "./artifacts",
    storageLayouts: ".storage-layouts",
  },

  storageLayoutConfig: {
    contracts: ["Cruize"],
    fullPath: false
  },

  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            runs: 200,
            enabled: true,
          },
        },
      },
    ],
    // compile file with give version
    overrides: {
      "contracts/gnosis-safe/safe.sol": {
        version: "0.7.6",
        settings: {},
      },
    },
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        accountsBalance: "100000000000000000000000000000000000000000",
        mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
      },
    },
    goerli: {
      ...sharedNetworkConfig,
      url: `https://goerli.infura.io/v3/${process.env.INFURA_KEY}`,
    },
    arbitrum_goerli: {
      ...sharedNetworkConfig,
      url: `https://arbitrum-goerli.infura.io/v3/${process.env.INFURA_KEY}`,
    },
    avalanche_fuji: {
      ...sharedNetworkConfig,
      url: `https://avalanche-fuji.infura.io/v3/${process.env.INFURA_KEY}`,
    },
    shardeum_testnet: {
      ...sharedNetworkConfig,
      url: `https://liberty20.shardeum.org/`,
    },

    //
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  watcher: {
    /* run npx hardhat watch compilation */
    compilation: {
      tasks: ["compile"],
      verbose: true,
    },
  },
  mocha: {
    timeout: 8000000,
  },
  /* run npx hardhat watch test */
  test: {
    tasks: [
      {
        command: "test",
        params: {
          logs: true,
          noCompile: false,
          testFiles: ["./test/src/cruize.test.ts"],
        },
      },
    ],
    files: ["./test/src/*"],
    verbose: true,
  },
  /* run npx hardhat watch ci */
  ci: {
    tasks: [
      "clean",
      { command: "compile", params: { quiet: true } },
      {
        command: "test",
        params: {
          noCompile: true,
          testFiles: ["./test/src/cruize.test.ts"],
        },
      },
    ],
  },
  //  shows gas in tables
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    gasPrice: 10,
  },
};

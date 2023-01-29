// import yargs from "yargs";
import * as dotenv from "dotenv";
import 'hardhat-deploy';
import 'hardhat-tracer';
import 'hardhat-watcher';
import "solidity-coverage";
import "@typechain/hardhat";
import 'hardhat-abi-exporter';
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomicfoundation/hardhat-toolbox";
import { HardhatUserConfig, task } from "hardhat/config";
import type { HttpNetworkUserConfig } from "hardhat/types";

dotenv.config({path:__dirname+'/.env'});


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});


// const argv = yargs.option("network", {
//   type: "string",
//   default: "hardhat"
// })
//   .help(false)
//   .version(false).argv;

const DEFAULT_MNEMONIC:string = process.env.MNEMONIC || "";

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

  solidity: {
    compilers: [
      {
        version: "0.8.6",
        settings: {
          optimizer: {
            runs: 200,
            enabled: true
          }
        }
      }
    ],
    // compile file with give version
    overrides: {
      "contracts/safe.sol": {
        version: "0.7.6",
        settings: { }
      }
    }
  },
  defaultNetwork: "hardhat",
  networks: {

    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        accountsBalance: "100000000000000000000000000000000000000000",
        mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC
      },
    },

    goerli: {
       ...sharedNetworkConfig,
        url: `https://goerli.infura.io/v3/${process.env.INFURA_KEY}`,
        chainId: 5,
    },
    
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  watcher: {
    /* run npx hardhat watch compilation */
    compilation: {
      tasks: ["compile"],
      verbose: true
    }},
  mocha: {
    timeout: 8000000,
  },
   /* run npx hardhat watch test */
   test: {
    tasks: [{
      command: 'test',
      params: {
        logs: true, noCompile: false,
        testFiles: [

          "./test/src/cruizevault.test.ts",

        ]
      }
    }],
    files: ['./test/src/*'],
    verbose: true
  },
    /* run npx hardhat watch ci */
  ci: {
    tasks: [
      "clean", { command: "compile", params: { quiet: true } },
      {
        command: "test",
        params: {
          noCompile: true,
          testFiles: [
            "./test/src/cruizevault.test.ts",

          ]
        }
      }],
  },
  //  shows gas in tables 
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    gasPrice: 10
  }

};
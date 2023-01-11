import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
import 'hardhat-tracer';
dotenv.config({path:__dirname+'/test.env'});

const DEFAULT_MNEMONIC:string = process.env.MNEMONIC || "";
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
      forking:{
        url:`https://mainnet.infura.io/v3/${process.env.INFURA_KEY}`

      }
    },
  
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
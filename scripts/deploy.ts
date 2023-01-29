

// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat

import { parseEther } from "ethers/lib/utils";

const { ethers } = require("hardhat");

// Runtime Environment's members available in the global scope.
const main = async () => {
    const crContract = await ethers.getContractFactory('CRTokenUpgradeable');
    const deployedContract =  await crContract.deploy();
    const cruizeContract = await ethers.getContractFactory("Cruize");
    console.log("cr contract ",deployedContract.address)
    const cruizevault = await cruizeContract.deploy("0x9A3310233aaFe8930d63145CC821FF286c7829e1","0xBe4C54c29f95786ca5e94ba9701FD5758183BFd4",deployedContract.address,parseEther("10"));
    console.log( "curize valut deployed at", cruizevault.address);

  };
  
  main()
    .then(() => {
      process.exit(0);
    })
    .catch((errr) => {
      console.log(errr);
      process.exit(0);
    });

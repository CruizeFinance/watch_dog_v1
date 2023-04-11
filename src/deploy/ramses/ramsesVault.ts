import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address, DeployFunction, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { contractNames } from "../../ts/deploy";
import { parseEther } from "ethers/lib/utils";
import { BigNumber, constants, Contract, utils } from "ethers";
import { verifyContract } from "../../utilites/utilites";
const deployContract: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  const { deployments } = hre;
  const { deploy, get } = deployments;
  const { RamsesVault, RamsesVaultProxy } = contractNames;

  let implementation: Deployment;
  let proxy: Deployment;
  let ramsesVault: Contract;
  const WETH = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  const USDC = "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8";

  let [deployer, signer] = await hre.ethers.getSigners();

  console.table({
    deployer: deployer.address,
    signer: signer.address,
  });

  //   Step-01 Deploy RamsesVault Implementation
  await deploy(RamsesVault, {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: false,
  });
  implementation = await get(RamsesVault);

  // Step-02 Deploy proxy
  await deploy(RamsesVaultProxy, {
    from: deployer.address,
    args: [implementation.address, deployer.address, "0x"],
    log: true,
    deterministicDeployment: false,
  });
  proxy = await get(RamsesVaultProxy);

  ramsesVault = await ethers.getContractAt(RamsesVault, proxy.address, signer);

  await ramsesVault.initialize(WETH, USDC, false, signer.address);

  console.table({
    proxy: proxy.address,
    ramsesVault: ramsesVault.address,
    implementation: implementation.address,
  });

  //   await verifyContract(hre, cruize.address, []);
};

export default deployContract;

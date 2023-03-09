import { Address, Deployment } from "hardhat-deploy/types";
import { BigNumber, Contract, Signer, constants } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { contractNames } from "../ts/deploy";
import { enableGnosisModule } from "../../test/src/helpers/utils";
import { chainTokenAddresses, crTokensDetiles } from "./constant";
const {
  CruizeVault,
  CruizeProxy,
  CrTokenMaster,
  MasterProxy,
  GnosisSafe,
} = contractNames;
const deployContracts = async (contractName: string, signer: Signer) => {
  const contract = await ethers.getContractFactory(contractName, signer);
  const deployedContract = await contract.deploy();
  return deployedContract;
};
const createCruizeToken = async (
  contract: Contract,
  name: string,
  symbol: string,
  decimal: number,
  tokenaddress: Address,
  tokenCap: string,
  owner: SignerWithAddress
) => {
  const res = await contract.createToken(
    name,
    symbol,
    tokenaddress,
    decimal,
    tokenCap
  );

  let tx = await res.wait();
  tx = await contract.connect(owner).cruizeTokens(tokenaddress);
  return tx;
};

const verifyContract = async (
  hre: HardhatRuntimeEnvironment,
  contractAddress: Address,
  constructorArgsParams: unknown[]
) => {
  try {
    await hre.run("verify", {
      address: contractAddress,
      constructorArgsParams: constructorArgsParams,
    });
  } catch (error) {
    console.log(error);
    console.log(
      `Smart contract at address ${contractAddress} is already verified`
    );
  }
};

const deployGnosis = async (hre: HardhatRuntimeEnvironment) => {
  // deploy gnosis ...
  const { deployments } = hre;
  const { deploy, get } = deployments;
  let [deployer, signer] = await hre.ethers.getSigners();
  let crToken: Deployment;
  let cruize: Deployment;
  let gnosisSafe: Deployment;
  let masterCopy: Deployment;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;
  //  deploying gnosis safe
  await deploy(GnosisSafe, {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: false,
  });

  gnosisSafe = await get(GnosisSafe);

  let singleton: Contract = await ethers.getContractAt(
    GnosisSafe,
    gnosisSafe.address,
    deployer
  );
  let encodedData = singleton.interface.encodeFunctionData("setup", [
    [deployer.address],
    1,
    "0x0000000000000000000000000000000000000000",
    "0x",
    "0x0000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000",
    0,
    "0x0000000000000000000000000000000000000000",
  ]);

  //  deploying master copy
  await deploy(MasterProxy, {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: false,
  });
  masterCopy = await get(MasterProxy);
  let masterProxy: Contract = await ethers.getContractAt(
    MasterProxy,
    masterCopy.address,
    deployer
  );

  let result = await masterProxy.createProxy(singleton.address, encodedData);
  let tx = await result.wait();
  gProxyAddress = tx.events[1].args["proxy"];
  //  get cruize safe
  cruizeSafe = await ethers.getContractAt(
    GnosisSafe,
    gProxyAddress as Address,
    signer
  );
  // await enableGnosisModule(cruizeSafe, cruizeModule.address, deployer);
  let paramsData: unknown[] = [singleton.address];
  await verifyContract(hre, gnosisSafe.address, []);
  await verifyContract(hre, masterCopy.address, []);

  return {
    cruizeSafe: cruizeSafe,
    MasterGnosisProxy: masterProxy,
  };
};
const createCRTokens = async (cruizeModule: Contract, chainId: string) => {
  for (let i = 0; i < crTokensDetiles.length; i++) {
    let tokenAddress = chainTokenAddresses[chainId][crTokensDetiles[i].tokenName]
    let crWBTC = await cruizeModule.callStatic.cruizeTokens(
      tokenAddress
    );

    if (crWBTC == constants.AddressZero)
      await cruizeModule.createToken(
        crTokensDetiles[i].crTokenName,
        crTokensDetiles[i].crSymbol,
        tokenAddress,
        crTokensDetiles[i].cap
      );
  }
};
export {
  deployContracts,
  createCruizeToken,
  verifyContract,
  deployGnosis,
  createCRTokens,
};
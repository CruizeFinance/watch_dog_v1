import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address, DeployFunction, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { contractNames } from "../ts/deploy";
import { parseEther } from "ethers/lib/utils";
import { BigNumber, constants, Contract, utils } from "ethers";
import abi from "ethereumjs-abi";
import { chainTokenAddresses } from "../utilites/constant";

import {
  createCRTokens,
  createCruizeToken,
  verifyContract,
} from "../utilites/utilites";
import { enableGnosisModule } from "../../test/src/helpers/utils";
const deployContract: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  const { deployments } = hre;
  const { deploy, get } = deployments;
  const { CruizeVault, CruizeProxy, CrTokenMaster, MasterProxy, GnosisSafe } =
    contractNames;
  let crToken: Deployment;
  let cruize: Deployment;
  let gnosisSafe: Deployment;
  let masterCopy: Deployment;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;

  let [deployer, signer] = await hre.ethers.getSigners();

  console.table({
    deployer:deployer.address,
    signer:signer.address
  });
  const chainId = await hre.getChainId();
  console.log("chainId: ",chainId)
  //  Gnosis safe address
  let cruizeSafeAddress: Address = "0x6C15abf7ca5E5a795ff246C3aa044236369b73A9";

  // Step-01 Deploy CrTokens Contract
  // await deploy(CrTokenMaster, {
  //   from: deployer.address,
  //   args: [],
  //   log: true,
  //   deterministicDeployment: false,
  // });
  // crToken = await get(CrTokenMaster);
  // deploy gnosis ...
  // if (chainId != "5") {
  //  deploying gnosis safe
  // await deploy(GnosisSafe, {
  //   from: deployer.address,
  //   args: [],
  //   log: true,
  //   deterministicDeployment: false,
  // });

  // gnosisSafe = await get(GnosisSafe);

  // let singleton: Contract = await ethers.getContractAt(
  //   GnosisSafe,
  //   gnosisSafe.address,
  //   deployer
  // );
  // let encodedData = singleton.interface.encodeFunctionData("setup", [
  //   [deployer.address],
  //   1,
  //   "0x0000000000000000000000000000000000000000",
  //   "0x",
  //   "0x0000000000000000000000000000000000000000",
  //   "0x0000000000000000000000000000000000000000",
  //   0,
  //   "0x0000000000000000000000000000000000000000",
  // ]);

  //  deploying master copy
  // await deploy(MasterProxy, {
  //   from: deployer.address,
  //   args: [],
  //   log: true,
  //   deterministicDeployment: false,
  // });
  // masterCopy = await get(MasterProxy);

  // let masterProxy: Contract = await ethers.getContractAt(
  //   MasterProxy,
  //   masterCopy.address,
  //   deployer
  // );

  // let result = await masterProxy.createProxy(singleton.address, encodedData);
  // let tx = await result.wait();
  // gProxyAddress = tx.events[1].args["proxy"];
  // //  get cruize safe
  // cruizeSafe = await ethers.getContractAt(
  //   GnosisSafe,
  //   cruizeSafeAddress as Address,
  //   signer
  // );
  // cruizeSafeAddress = cruizeSafe.address;
  // let paramsData: unknown[] = [singleton.address];

  // Step-02 Deploy Cruize Implementation Contract
  await deploy(CruizeVault, {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: false,
  });
  cruize = await get(CruizeVault);
  console.log('cruize',cruize.address)

  // Step-03 Deploy Cruize Proxy Contract
 /* await deploy(CruizeProxy, {
    from: deployer.address,
    args: [cruize.address, deployer.address, "0x"],
    log: true,
    deterministicDeployment: false
  });
  const cruizeProxy = await get(CruizeProxy);

  const cruizeModuleProxy = await ethers.getContractAt(
    "CruizeProxy",
    cruizeProxy.address,
    deployer
  );

  // Step-04 Call setUp function to initialize the contract.
  const encoder = new ethers.utils.AbiCoder();
  const encodedParams = encoder.encode(
    [
      "address",
      "address",
      "address",
      "address",
      "address",
      "uint256",
      "uint256",
    ],
    [
      signer.address, // owner
      cruizeSafeAddress as Address, // gnosis safe
      crToken.address, // crTokens
      cruizeModuleProxy.address, // cruizeProxy
      cruize.address, // cruize implementation
      parseEther("2"), // management fee
      parseEther("10"), // performance fee
    ]
  );
  const cruizeModule: Contract = await ethers.getContractAt(
    "Cruize",
    cruizeModuleProxy.address,
    signer
  );

  // await cruizeModuleProxy.connect(deployer).upgradeTo(cruize.address);

  try {
    await cruizeModule.connect(signer).setUp(encodedParams);
  } catch (error) {
    console.log(`contract already initialized`);
  }

  // await verifyContract(hre, cruizeModuleProxy.address, [
  //   cruize.address,
  //   signer.address,
  //   "0x"]);

  await createCRTokens(cruizeModule, chainId);

  // await enableGnosisModule(cruizeSafe, cruizeModule.address, deployer);

  console.table({
    crToken: crToken.address,
    gnosisSafe: cruizeSafeAddress,
    cruizeImplementation: cruize.address,
    cruizeProxy: cruizeModuleProxy.address,
    eth: chainTokenAddresses[chainId]["ETH"],
    weth: chainTokenAddresses[chainId]["WETH"],
    wbtc: chainTokenAddresses[chainId]["WBTC"],
    usdc: chainTokenAddresses[chainId]["USDC"],
  });
  await verifyContract(hre, crToken.address, []);
  // await verifyContract(hre, gnosisSafe.address, []);
  // // await verifyContract(hre, masterCopy.address, []);
    await verifyContract(hre, cruizeProxy.address, [
    cruize.address,
    deployer.address,
    "0x",
  ]);
  */
  await verifyContract(hre, cruize.address, []);

};

export default deployContract;
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { deployContracts } from "../utilites/common.test";
import { isAddress, parseEther } from "ethers/lib/utils";
import { Address } from "hardhat-deploy/types";
import abi from "ethereumjs-abi";
import { BigNumber, Contract } from "ethers";

async function deployCruizeContract(adminSigner: SignerWithAddress,deployer:SignerWithAddress) {
  const singleton = await deployContracts("GnosisSafe", adminSigner);
  const masterProxy = await deployContracts(
    "contracts/gnosis-safe/Gnosis-proxy.sol:GnosisSafeProxyFactory",
    adminSigner
  );
  const dai = await deployContracts("daiMintable", adminSigner);
  const crContract = await deployContracts("CRTokenUpgradeable", adminSigner);

  let encodedData = singleton.interface.encodeFunctionData("setup", [
    [adminSigner.address],
    1,
    "0x0000000000000000000000000000000000000000",
    "0x",
    "0x0000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000",
    0,
    "0x0000000000000000000000000000000000000000",
  ]);
  const gnosisProxy = await masterProxy.createProxy(
    singleton.address,
    encodedData
  );

  let tx = await gnosisProxy.wait();
  const gProxyAddress = tx.events[1].args["proxy"];
  const cruizeSafe = await ethers.getContractAt(
    "contracts/gnosis-safe/safe.sol:GnosisSafe",
    gProxyAddress as Address,
    adminSigner
  );

  const CRUIZELOGIC = await ethers.getContractFactory("Cruize", adminSigner);

  const cruizeLogic = await CRUIZELOGIC.deploy();
  // const cruizeModule =  await ethers.getContractAt("Cruize")
  const cruizeProxy = await ethers.getContractFactory(
    "CruizeProxy",
    adminSigner
  );
  const cruizeModuleProxy = await cruizeProxy.deploy(
    cruizeLogic.address,
    deployer.address,
    "0x"
  );
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
      adminSigner.address,
      gProxyAddress as Address,
      crContract.address,
      cruizeModuleProxy.address,
      cruizeLogic.address,
      parseEther("2"),
      parseEther("10"),
    ]
  );
  const cruizeModule: Contract = await ethers.getContractAt(
    "Cruize",
    cruizeModuleProxy.address
  );
  await cruizeModule.setUp(encodedParams);
  await dai.mint(parseEther("100000"));

  const CruizeContract = {
    CruizeSafe: cruizeSafe,
    cruizeModule: cruizeModule,
    gProxyAddress: gProxyAddress,
    singleton: singleton,
    dai: dai,
    cruizeLogic: cruizeLogic,
    cruizeModuleProxy: cruizeModuleProxy,

    crContract,
  };
  // console.log(CruizeContract)
  return CruizeContract;
}

const enableGnosisModule = async (
  cruizeSafe: Contract,
  cruizeModule: Address,
  signer: SignerWithAddress
) => {
 console.log("enableGnosisModule......")

  const data = abi.simpleEncode("enableModule(address)", cruizeModule);
  let hexData = "0x" + data.toString("hex");
  console.log(hexData)

  const signature =
    "0x000000000000000000000000" +
    signer.address.slice(2) +
    "0000000000000000000000000000000000000000000000000000000000000000" +
    "01";
  const tx = await cruizeSafe.connect(signer).execTransaction(
    cruizeSafe.address,
    0,
    hexData,
    0,
    0,
    0,
    0,
    "0x0000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000",
    signature
  );
  return tx;
};

const calculatePricePerShare = async (
  totalSupply: BigNumber,
  pendingAmount: BigNumber,
  totalBalance: BigNumber,
  decimal: number
) => {
  const tokenTotalSupply: number = BNtoNumber(totalSupply, decimal);
  const vaultTotalBalance: number = BNtoNumber(totalBalance, decimal);
  const vaultPendingBalance: number = BNtoNumber(pendingAmount, decimal);
  const lockedBalance: number = vaultTotalBalance - vaultPendingBalance;
  return tokenTotalSupply > 0 ? lockedBalance / tokenTotalSupply : 1;
};

const BNtoNumber = (number: BigNumber, decimal: number) => {
  return Number(ethers.utils.formatUnits(number, decimal));
};
export { enableGnosisModule, deployCruizeContract, calculatePricePerShare };

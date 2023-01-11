import { expect } from "chai";
import { Contract } from "ethers";
import hre, { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "hardhat-deploy/dist/types";
import abi from 'ethereumjs-abi';

describe("testing Gnosis Trnasfer fund", function () {
  let signer: SignerWithAddress;
  let singleton: Contract;
  let masterProxy: Contract;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;
  let cruizeModule: Contract;
  let user1:SignerWithAddress;
  const gnosisAddress:Address = "0xBe4C54c29f95786ca5e94ba9701FD5758183BFd4";
  const gnosisOwnerAddress:Address = "0x9A3310233aaFe8930d63145CC821FF286c7829e1";
  //  proyxFunctionData  -  it's the hex from of functino name that we have to call on the safe contract and it's parameters.
  const proyxFunctionData =
    "0xb63e800d00000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000048f91fbc86679e14f481dd3c3381f0e07f93a7110000000000000000000000000000000000000000000000000000000000000000";
  before(async () => {
    [signer,user1] = await ethers.getSigners();
    //  deploy GnosisSafe
    const SINGLETON = await ethers.getContractFactory("GnosisSafe", signer);
    singleton = await SINGLETON.deploy();
    //  deploy MASTERPROXY

    const MASTERPROXY = await ethers.getContractFactory(
      "contracts/proxy.sol:GnosisSafeProxyFactory",
      signer
    );
    masterProxy = await MASTERPROXY.deploy();

    let res = await masterProxy.createProxy(
      singleton.address,
      proyxFunctionData
    );
    let tx = await res.wait();
    gProxyAddress = tx.events[1].args["proxy"];
    console.log(gProxyAddress);
    //  get cruizeSafe
    cruizeSafe = await ethers.getContractAt(
      "GnosisSafe",
      gProxyAddress as Address,
      signer
    );
    console.log(typeof masterProxy);

    const CRUIZEMODULE = await ethers.getContractFactory("CruizeVault", signer);
    //  signer.address -  a user's that can perfome only functions on safe.
    // gProxyAddress -  address of gnosis  safe.
    cruizeModule = await CRUIZEMODULE.deploy(signer.address, gProxyAddress);
    hre.tracer.nameTags[cruizeSafe.address] = 'Cruize safe'
    hre.tracer.nameTags[singleton.address] = 'singleton'
    hre.tracer.nameTags[gProxyAddress as Address] = 'gProxyAddress'
    hre.tracer.nameTags[cruizeModule.address] = 'cruizeModule'
    hre.tracer.nameTags[user1.address] = 'userOne'
    hre.tracer.nameTags[signer.address] = 'singer'
   
  });

  it("approve moudle on gnosis", async () => {
    // cruizeModule -  deployed address of Cruize module.
    const data = abi.simpleEncode("enableModule(address)",cruizeModule.address);
    let hexData = data.toString("hex")
    hexData = '0x'+hexData
    const signature =  "0x000000000000000000000000" + signer.address.slice(2) + "0000000000000000000000000000000000000000000000000000000000000000" + "01"
    let res =  await cruizeSafe.execTransaction(
      cruizeSafe.address,
      0,
     hexData,
      0,
      0,
      0,
      0,
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      signature
      )
      res = await res.wait()
      console.log(res.events[1].args)
     
    // let tx = res.wait();
    // console.log("tx", tx);
  });
  it("send funds to Safe",async()=>{
    let tx = {
      to: cruizeSafe.address,
      // Convert currency unit from ether to wei
      value: ethers.utils.parseEther('20')
  }
    let res  = await signer.sendTransaction(tx);
    let tnx  =  await res.wait()
    console.log('fund transfer to gnosis',tnx)

  })
  it("send money  using module",async ()=>{

    // const data = abi.simpleEncode("sendmoney(address,uint256,bytes,Enum.Operation)",cruizeModule.address);
    
    let res =  await cruizeModule.sendmoney(cruizeSafe.address,ethers.utils.parseEther("1"),'0x',0);
    let tx =  await res.wait()
    console.log(tx)
  })
});

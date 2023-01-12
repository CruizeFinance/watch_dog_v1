import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import hre, { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "hardhat-deploy/dist/types";
import abi from "ethereumjs-abi";
import { parseEther } from "ethers/lib/utils";

describe("testing Gnosis Trnasfer fund", function () {
  let signer: SignerWithAddress;
  let singleton: Contract;
  let masterProxy: Contract;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;
  let cruizeModule: Contract;
  let dai: Contract;
  let crContract:Contract;
  let user1: SignerWithAddress;
  const gnosisAddress: Address = "0xBe4C54c29f95786ca5e94ba9701FD5758183BFd4";
  const gnosisOwnerAddress: Address =
    "0x9A3310233aaFe8930d63145CC821FF286c7829e1";
  //  proyxFunctionData  -  it's the hex from of functino name that we have to call on the safe contract and it's parameters.
  const proyxFunctionData =
    "0xb63e800d00000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000048f91fbc86679e14f481dd3c3381f0e07f93a7110000000000000000000000000000000000000000000000000000000000000000";
  before(async () => {
    [signer, user1] = await ethers.getSigners();
    const CRCONTRACT  = await ethers.getContractFactory("CRTokenUpgradeable", signer);
    crContract = await CRCONTRACT.deploy();
    //  deploy GnosisSafe
    const SINGLETON = await ethers.getContractFactory("GnosisSafe", signer);
    singleton = await SINGLETON.deploy();
    //  deploy MASTERPROXY

    const MASTERPROXY = await ethers.getContractFactory(
      "contracts/proxy.sol:GnosisSafeProxyFactory",
      signer
    );
    masterProxy = await MASTERPROXY.deploy();

    const DAI = await ethers.getContractFactory("DAI", signer);
    dai = await DAI.deploy();

    let res = await masterProxy.createProxy(
      singleton.address,
      proyxFunctionData
    );
    let tx = await res.wait();
    gProxyAddress = tx.events[1].args["proxy"];
   
    //  get cruizeSafe
    cruizeSafe = await ethers.getContractAt(
      "GnosisSafe",
      gProxyAddress as Address,
      signer
    );
   

    const CRUIZEMODULE = await ethers.getContractFactory("Cruize", signer);
    //  signer.address -  a user's that can perfome only functions on safe.
    // gProxyAddress -  address of gnosis  safe.
   
    cruizeModule = await CRUIZEMODULE.deploy(signer.address, gProxyAddress,crContract.address);
 

    hre.tracer.nameTags[cruizeSafe.address] = "Cruize safe";
    hre.tracer.nameTags[singleton.address] = "singleton";
    hre.tracer.nameTags[gProxyAddress as Address] = "gProxyAddress";
    hre.tracer.nameTags[cruizeModule.address] = "cruizeModule";
    hre.tracer.nameTags[user1.address] = "userOne";
    hre.tracer.nameTags[signer.address] = "singer";

  });
 
  it("approve moudle on gnosis", async () => {
    // cruizeModule -  deployed address of Cruize module.
    const data = abi.simpleEncode(
      "enableModule(address)",
      cruizeModule.address
    );
    let hexData = data.toString("hex");
    hexData = "0x" + hexData;
    const signature =
      "0x000000000000000000000000" +
      signer.address.slice(2) +
      "0000000000000000000000000000000000000000000000000000000000000000" +
      "01";
    let res = await cruizeSafe.execTransaction(
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
  
  });
  it("send funds to Safe", async () => {

    let tx = {
      to: cruizeSafe.address,
      // Convert currency unit from ether to wei
      value: ethers.utils.parseEther("20"),
    };
    let res = await signer.sendTransaction(tx);
    await dai.transfer(cruizeSafe.address, parseEther("100"));
  });


  it('create crtokens',async()=>{
  let res =  await cruizeModule.createToken("cruzie Dai",'crdai',dai.address,18)
  let tx = await res.wait()
    tx =  await cruizeModule.cruizeTokens(dai.address)
    hre.tracer.nameTags[tx] = "crDai";
   res =  await cruizeModule.createToken("cruzie ETH",'crETH',ethers.constants.AddressZero,18)
    tx = await res.wait()
      tx =  await cruizeModule.cruizeTokens(ethers.constants.AddressZero)
      
    hre.tracer.nameTags[tx] = "CRETH";
  })
  

  it('deposit ERC20 token to contract',async()=>{
    await dai.approve(cruizeModule.address,parseEther('10'))
     await cruizeModule.deposit(dai.address,parseEther("5"));
    
    
  })
  it('deposit ETH token to contract',async()=>{
     await cruizeModule.deposit(ethers.constants.AddressZero,parseEther("1"),{value:parseEther("1")})
   
    
  })
  it("withdraw ERC20  using module", async () => {

    const data = abi.rawEncode(
      ['address','address','uint256'],
     [ dai.address,
      signer.address,
      100000000000000]
    );

    await cruizeModule.withdraw(
      cruizeModule.address,
      "0x" + data.toString("hex"),
      1
    );
  
  });
  it("withdraw ETH  using module", async () => {
    const data = abi.rawEncode(
      ['address','address','uint256'],
      [  ethers.constants.AddressZero,
        signer.address,
        50000000000000]
    
    );

    let res = await cruizeModule.withdraw(
      cruizeModule.address,
      "0x" + data.toString("hex"),
      1
    );

  });


});

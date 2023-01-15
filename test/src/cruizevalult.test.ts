import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import hre, { ethers } from "hardhat";
import { DepositERC20, createCruizeToken, depoloyContracts } from "./utilites/common.test";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "hardhat-deploy/dist/types";
import abi from "ethereumjs-abi";
import { parseEther } from "ethers/lib/utils";
import { ETHADDRESS } from "./utilites/constant";
import { parse } from "path";
import { constants } from "buffer";

/***
 * 1.  deploy contract
 * 2. approve moduel to get access of the gnosis fund.
 * 3. send funds to safe.
 * 4. create CRTOKENS for allowed asset's
 * 5. deposit ERC20 tokens  and ETH coin on  Cruize Vault.
 * 6. withdrawa tokens from vault.
 * test on edge case's.
 *
 *
 *
 *
 */
describe("testing Gnosis Trnasfer fund", function () {
  let signer: SignerWithAddress;
  let singleton: Contract;
  let masterProxy: Contract;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;
  let cruizeModule: Contract;
  let dai: Contract;
  let crContract: Contract;
  let user1: SignerWithAddress;

  //  proyxFunctionData  -  it's the hex from of functino name that we have to call on the safe contract and it's parameters.
  const proyxFunctionData =
    "0xb63e800d00000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000048f91fbc86679e14f481dd3c3381f0e07f93a7110000000000000000000000000000000000000000000000000000000000000000";
  before(async () => {
    [signer, user1] = await ethers.getSigners();
    crContract = await depoloyContracts("CRTokenUpgradeable", signer);

    singleton = await depoloyContracts("GnosisSafe", signer);
    //  deploy MASTERPROXY
    masterProxy = await depoloyContracts(
      "contracts/proxy.sol:GnosisSafeProxyFactory",
      signer
    );
    dai = await depoloyContracts("DAI", signer);
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

    //  signer.address -  a user's that can perfome only functions on safe.
    // gProxyAddress -  address of gnosis  safe.

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
  // it("send funds to Safe", async () => {
  //   let tx = {
  //     to: cruizeSafe.address,
  //     // Convert currency unit from ether to wei
  //     value: ethers.utils.parseEther("20"),
  //   };
  //   let res = await signer.sendTransaction(tx);
  //   await dai.transfer(cruizeSafe.address, parseEther("100"));
  // });

  it("create crtokens", async () => {
    
    let tx =  await createCruizeToken( cruizeModule,"cruzie Dai","crdai",   18, dai.address,)
    hre.tracer.nameTags[tx] = "crDai";
     tx =  await createCruizeToken( cruizeModule,"cruzie ETH",  "crETH",  18, ETHADDRESS,)
    tx = await cruizeModule.cruizeTokens(ETHADDRESS);

    hre.tracer.nameTags[tx] = "CRETH";
  });

  it("deposit ERC20 token to contract", async () => {
    await DepositERC20(cruizeModule,dai,"10");
 
  });

  it("deposit ETH coin to contract", async () => {
    await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
      value: parseEther("1"),
    });
  });
  /**
   * make an wihtdrawal request before the round closed  , once the round close try to withdrawa fund.
   * withdrawa intstantly just after depositing the funds.
   * complete the withdrawal .
   * withrawal with invaild address
   * withdrawal with zero address
   * withdrawal with zero amount
   * in the frist round user will deposit and in the second round we will protect them.
   */
  it('withdrawInstantly if cruizemoduel address is null', async() => {
    await cruizeModule.withdrawInstantly (ethers.constants.AddressZero,parseEther("1"),ETHADDRESS)
  });
  it('withdrawInstantly if cruizemoduel address is null', async() => {
    // await cruizeModule.withdrawInstantly (ethers.constants.AddressZero,parseEther("1000"),dai.address)
  });

  it('withdrawInstantly if amount is zero', async() => {
    await expect (cruizeModule.withdrawInstantly (cruizeSafe.address,parseEther("0"),ETHADDRESS)).to.be.revertedWithCustomError(cruizeModule,"ZeroAmount").withArgs(0)

  });
  it('withdrawInstantly if token address is null', async() => {
    await expect (cruizeModule.withdrawInstantly (cruizeSafe.address,parseEther("1"),ethers.constants.AddressZero)).to.be.revertedWithCustomError(cruizeModule,"AssetNotAllowed").withArgs(ethers.constants.AddressZero)
  });

  it("close round", async () => {
    await cruizeModule.closeRound(ETHADDRESS);
  });

  it("withdrawInstantly if round is not same",async()=>{
    await expect (cruizeModule.withdrawInstantly (cruizeSafe.address,parseEther("1"),ETHADDRESS)).to.be.revertedWithCustomError(cruizeModule,"InvalidWithdrawalRound").withArgs(1,2)
  })
  // if round is not same .
  // token is not allowed .
  // amoun is grater  then what you have deposited.

  it('withdrawInstantly just after deposit', async() => {
    await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
      value: parseEther("1"),
    });
    await cruizeModule.withdrawInstantly(cruizeSafe.address,parseEther("1"),ETHADDRESS)
  });

  it('withdrawInstantly just after deposit when withdrawal amount is higher then deposit', async() => {

    await cruizeModule.deposit(ETHADDRESS, parseEther("3"), {
      value: parseEther("3"),
    });
    await expect( cruizeModule.withdrawInstantly(cruizeSafe.address,parseEther("4"),ETHADDRESS)).to.be.revertedWithCustomError(cruizeModule,"NotEnoughWithdrawalBalance").withArgs(parseEther("3"),parseEther("4"))
  });


  it('withdrawInstantly if asset is not allowed', async() => {

    await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
      value: parseEther("3"),
    });
    await expect( cruizeModule.withdrawInstantly(cruizeSafe.address,parseEther("4"),ethers.constants.AddressZero)).to.be.revertedWithCustomError(cruizeModule,"AssetNotAllowed").withArgs(ethers.constants.AddressZero)
  });

  //  intiate witharawal with wrong token address
  /**
   * intiate withrawal more  amount then you deposit
   * intiate withrawal  zero token address
   * intitate if token is not allowed
   */

  it('intiate withdaral with wrong withdrawal amount', async() => {
    await expect( cruizeModule.initiateWithdrawal(parseEther("2000"),dai.address)).to.be.revertedWith('NOT ENOUGH TOKEN BALANCE')
  });
  it('intiate withdaral if  token is not allowed', async() => {
    await expect(cruizeModule.initiateWithdrawal(parseEther("100"),cruizeModule.address)).to.be.revertedWithCustomError(cruizeModule,"AssetNotAllowed").withArgs(cruizeModule.address)
  });
  it('intiate withdaral  when withdrawal amount is more then what user deposit', async() => {
   cruizeModule.initiateWithdrawal(parseEther("100"),dai.address)
  });
  it('intiate withdaral  ', async() => {
    cruizeModule.initiateWithdrawal(100000000000000,dai.address)
   });
  it('complete withdrawal when Round is not closed', async() => {


        const data = abi.rawEncode(
      ["address", "address", "uint256"],
      [dai.address, signer.address, 100000000000000]
    );
   await 
    await  expect( cruizeModule.withdraw(dai.address,cruizeSafe.address, "0x" + data.toString("hex")))
    .to.be.revertedWithCustomError(cruizeModule,"InvalidWithdrawalRound").withArgs(1,1)
    
  });

  it("close round DAI", async () => {
    await cruizeModule.closeRound(dai.address);
  });

  it('complete withdrawal after Round has been closed', async() => {
    const data = abi.rawEncode(
  ["address", "address", "uint256"],
  [dai.address, signer.address,100000000000000 ]
);
await cruizeModule.withdraw(dai.address,cruizeSafe.address, "0x" + data.toString("hex"))

});
  // it("withdraw ERC20  using module", async () => {
  //   const data = abi.rawEncode(
  //     ["address", "address", "uint256"],
  //     [dai.address, signer.address, 100000000000000]
  //   );

  //   await cruizeModule.withdraw(
  //     cruizeModule.address,
  //     "0x" + data.toString("hex")
  //   );
  // });
  // it("withdraw ETH  using module", async () => {
  //   const data = abi.rawEncode(
  //     ["address", "address", "uint256"],
  //     [ethers.constants.AddressZero, signer.address, 50000000000000]
  //   );

  //   let res = await cruizeModule.withdraw(
  //     cruizeModule.address,
  //     "0x" + data.toString("hex")
  //   );
  // });
});

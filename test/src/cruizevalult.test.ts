import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import hre, { ethers } from "hardhat";
import {
  DepositERC20,
  createCruizeToken,
  deployContracts,
} from "./utilites/common.test";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "hardhat-deploy/dist/types";
import abi from "ethereumjs-abi";
import { parseEther } from "ethers/lib/utils";


describe("work flow from curize vault to cruize contract", function () {
  let signer: SignerWithAddress;
  let singleton: Contract;
  let masterProxy: Contract;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;
  let cruizeModule: Contract;
  let dai: Contract;
  let crContract: Contract;
  let user1: SignerWithAddress;

  let ETHADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  //  proxyFunctionData  -  it's the hex from of function name that we have to call on the safe contract and it's parameters.
  const proyxFunctionData =
    "0xb63e800d00000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000048f91fbc86679e14f481dd3c3381f0e07f93a7110000000000000000000000000000000000000000000000000000000000000000";
  before(async () => {
    [signer, user1] = await ethers.getSigners();
    crContract = await deployContracts("CRTokenUpgradeable", signer);

    singleton = await deployContracts("GnosisSafe", signer);

    masterProxy = await deployContracts(
      "contracts/gnosis-safe/Gnosis-proxy.sol:GnosisSafeProxyFactory",
      signer
    );
    dai = await deployContracts("DAI", signer);
    let res = await masterProxy.createProxy(
      singleton.address,
      proyxFunctionData
    );
    let tx = await res.wait();
    gProxyAddress = tx.events[1].args["proxy"];

    cruizeSafe = await ethers.getContractAt(
      "contracts/safe.sol:GnosisSafe",
      gProxyAddress as Address,
      signer
    );

    const CRUIZEMODULE = await ethers.getContractFactory("Cruize", signer);

    cruizeModule = await CRUIZEMODULE.deploy(
      signer.address,
      gProxyAddress,
      crContract.address
    );

    hre.tracer.nameTags[cruizeSafe.address] = "Cruize safe";
    hre.tracer.nameTags[singleton.address] = "singleton";
    hre.tracer.nameTags[gProxyAddress as Address] = "gProxyAddress";
    hre.tracer.nameTags[cruizeModule.address] = "cruizeModule";
    hre.tracer.nameTags[user1.address] = "userOne";
    hre.tracer.nameTags[signer.address] = "singer";
  });

  describe("setting up env",()=>{
    it.only("approve module on gnosis", async () => {
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
    it.only("create crtokens", async () => {
      let tx = await createCruizeToken(
        cruizeModule,
        "cruzie Dai",
        "crdai",
        18,
        dai.address
      );
      hre.tracer.nameTags[tx] = "crDai";
      tx = await createCruizeToken(
        cruizeModule,
        "cruzie ETH",
        "crETH",
        18,
        ETHADDRESS
      );
      tx = await cruizeModule.cruizeTokens(ETHADDRESS);
  
      hre.tracer.nameTags[tx] = "CRETH";
    });
  })



  describe("frist deposit round", ()=>{
    it.only("deposit ERC20 token to contract in 1st Deposit Round", async () => {
      await DepositERC20(cruizeModule, dai, "10");
      const vault = await cruizeModule.callStatic.vaults(dai.address);
      expect(vault.round).to.be.equal(1);
      expect(vault.lockedAmount).to.be.equal(0);
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
  
      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        dai.address
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("10"));
      expect(receipt.lockedAmount).to.be.equal(parseEther("0"));
    });

    it.only("deposit ETH coin to contract in frist round", async () => {
      await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
        value: parseEther("1"),
      });
  
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(1);
      expect(vault.lockedAmount).to.be.equal(0);
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
  
      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("1"));
      expect(receipt.lockedAmount).to.be.equal(parseEther("0"));
    });
    it.only("initiateWithdrawal if  1st deposit Round is not Closed", async () => {
      await expect(cruizeModule.initiateWithdrawal(parseEther("1"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
        .withArgs(1, 1);
      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );
      console.log(withdrawal);
      expect(withdrawal.round).to.be.equal(0);
      expect(withdrawal.amount).to.be.equal(BigNumber.from(0));
      expect(
        await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
      ).to.be.equal(BigNumber.from(0));
    });
  
    it.only("close  1st ETH Deposit  round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
    });
  }

  
  )
  describe("2nd round",()=>{
    it.only("deposit ETH coin to contract in 2nd round", async () => {
      await cruizeModule.deposit(ETHADDRESS, parseEther("2"), {
        value: parseEther("2"),})
      });
     it.only("close  2st ETH round", async () => {
        await cruizeModule.closeRound(ETHADDRESS);
      });
  })

 describe('3rd round and initiate withdrawal', () => {

  it.only("initiateWithdrawal if ETH 3rd Round is Closed", async () => {
    await cruizeModule.initiateWithdrawal(parseEther("3"), ETHADDRESS);

    const withdrawal = await cruizeModule.callStatic.withdrawals(
      signer.address,
     ETHADDRESS
    );
    console.log(withdrawal);
    expect(withdrawal.round).to.be.equal(3);
    expect(withdrawal.amount).to.be.equal(parseEther("3"));
    expect(
      await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
    ).to.be.equal(parseEther("3"));
  });
  it.only("close  3st ETH Deposit  round", async () => {
    await cruizeModule.closeRound(ETHADDRESS);
  });
  it.only("complete withdrawal of 3rd Round", async () => {
   const abiEncoder =  new ethers.utils.AbiCoder()
     const data =  abiEncoder.encode(  
        ["address", "uint256"],
      [ signer.address, parseEther('3')])
   console.log(data)
    await cruizeModule.withdraw(
      ETHADDRESS,
      cruizeSafe.address,
      data
      // "0x" + data.toString("hex")
    );
  });
 });




  describe("round 4 :  testing instant withdrawal",()=>{
    it.only("deposit ETH coin to contract in 4nd round to test instant withdrawal", async () => {
      await cruizeModule.deposit(ETHADDRESS, parseEther("2"), {
        value: parseEther("2"),})
      });
    it.only("withdrawInstantly if cruizemodule address is null", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          ethers.constants.AddressZero,
          parseEther("2"),
          ETHADDRESS
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "InvalidVaultAddress")
        .withArgs(ethers.constants.AddressZero);
    });
  
    it.only("withdrawInstantly if amount is zero", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          cruizeSafe.address,
          parseEther("0"),
          ETHADDRESS
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "ZeroAmount")
        .withArgs(0);
    });
  
    it.only("withdrawInstantly if token address is null", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          cruizeSafe.address,
          parseEther("1"),
          ethers.constants.AddressZero
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });
  
    it.only("close 4th ETH  round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
    });
  
    it.only("withdrawInstantly if round is not same", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          cruizeSafe.address,
          parseEther("1"),
          ETHADDRESS
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
        .withArgs(4, 5);
    });
  
    
  
  })


describe('round 5 : testing  withdrawInstantly with  edge case', () => {
  it.only("deposit ETH coin to contract in 5 round", async () => {
    await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
      value: parseEther("1"),})
    });


  it.only("withdrawInstantly just after deposit if withdrawal amount is greater than deposit", async () => {


    await expect(
      cruizeModule.withdrawInstantly(
        cruizeSafe.address,
        parseEther("4"),
        ETHADDRESS
      )
    )
      .to.be.revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalBalance")
      .withArgs(parseEther("1"), parseEther("4"));
  });

  it.only("withdrawInstantly if asset is not allowed", async () => {

    await expect(
      cruizeModule.withdrawInstantly(
        cruizeSafe.address,
        parseEther("4"),
        ethers.constants.AddressZero
      )
    )
      .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
      .withArgs(ethers.constants.AddressZero);
  });
  it.only("withdrawInstantly just after deposit", async () => {
    const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
    console.log(vault.lockedAmount);
    // expect(vault.lockedAmount).to.be.equal(2000300000000000000);

    await cruizeModule.withdrawInstantly(
      cruizeSafe.address,
      parseEther("1"),
      ETHADDRESS
    );
  });
    
  it.only("close 5th ETH  round", async () => {
    await cruizeModule.closeRound(ETHADDRESS);
  });
  

});



 
   
  

describe('round 6: testing withdrawal', () => {
  it.only("initiateWithdrawal if withdrawal amount is greater than  the deposited amount", async () => {
    await expect(
      cruizeModule.initiateWithdrawal(parseEther("2000"), ETHADDRESS)
    )
      .to.be.revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalBalance")
      .withArgs(parseEther("5"), parseEther("2000"));
  });
  it.only("initiateWithdrawal if  token is not allowed", async () => {
    await expect(
      cruizeModule.initiateWithdrawal(parseEther("100"), cruizeModule.address)
    )
      .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
      .withArgs(cruizeModule.address);
  });
  it.only("complete withdrawal when  withdrawal is not initiate", async () => {
    const data = abi.rawEncode(
      ["address", "uint256"],
      [ signer.address, 100000000000000]
    );
    await expect(
      cruizeModule.withdraw(
        dai.address,
        cruizeSafe.address,
        "0x" + data.toString("hex")
      )
    )
      .to.be.revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalBalance")
      .withArgs(0, 100000000000000);
  });

  it.only("get total withdrawal amount for given asset", async () => {
    let res = await cruizeModule.vaults(dai.address);
    // console.log("total withdrawal amount for an round", res)
  });



  it.only("initiateWithdrawal for ETH ", async () => {
    await cruizeModule.initiateWithdrawal(parseEther("5"), ETHADDRESS);

    const withdrawal = await cruizeModule.callStatic.withdrawals(
      signer.address,
      ETHADDRESS
    );
    console.log(withdrawal);
    expect(withdrawal.round).to.be.equal(6);
    expect(withdrawal.amount).to.be.equal(parseEther("5"));
    expect(
      await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
    ).to.be.equal(parseEther("5"));
  });
  it.only("close 6th ETH  round", async () => {
    await cruizeModule.closeRound(ETHADDRESS);
  });
  it.only("initiateWithdrawal if you already  made and withdrawal request", async () => {
    await expect(cruizeModule.initiateWithdrawal(parseEther("1"),ETHADDRESS))
      .to.be.revertedWithCustomError(cruizeModule, "WithdrawalAlreadyExists")
      .withArgs(parseEther("5"));
  });
  it.only("complete withdrawal if Dai 1st Protection Round has been closed", async () => {
    const abiEncoder =  new ethers.utils.AbiCoder()
    const data =  abiEncoder.encode(  
       ["address", "uint256"],
     [ signer.address, parseEther('3')])
    await cruizeModule.withdraw(
      ETHADDRESS,
      cruizeSafe.address,
      data
    );
  });
  
});








  



 
 
  // it.only("complete withdrawal if Dai 1st Protection is Round not closed", async () => {
  //   const data = abi.rawEncode(
  //     ["address", "uint256"],
  //     [signer.address, 100000000000000]
  //   );
  //   await expect(
  //     cruizeModule.withdraw(
  //       dai.address,
  //       cruizeSafe.address,
  //       "0x" + data.toString("hex")
  //     )
  //   )
  //     .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
  //     .withArgs(2, 2);
  // });

  // it.only("withdrawinstantly in the 1st  Protection round of Dai ", async () => {
  //   const vault = await cruizeModule.callStatic.vaults(dai.address);
  //   expect(vault.lockedAmount).to.be.equal(parseEther("10"));
  //   await expect(
  //     cruizeModule.withdrawInstantly(
  //       cruizeSafe.address,
  //       parseEther("10"),
  //       dai.address
  //     )
  //   )
  //     .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
  //     .withArgs(1, 2);
  // });
  
  // it.only("close Dai 1st Protection Round", async () => {
  //   await cruizeModule.closeRound(dai.address);
  // });



});

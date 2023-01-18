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

  before(async () => {
    [signer, user1] = await ethers.getSigners();

    dai = await deployContracts("DAI", signer);
    singleton = await deployContracts("GnosisSafe", signer);
    crContract = await deployContracts("CRTokenUpgradeable", signer);

    masterProxy = await deployContracts(
      "contracts/gnosis-safe/Gnosis-proxy.sol:GnosisSafeProxyFactory",
      signer
    );

    let encodedData = singleton.interface.encodeFunctionData("setup", [
      [signer.address],
      1,
      "0x0000000000000000000000000000000000000000",
      "0x",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      0,
      "0x0000000000000000000000000000000000000000",
    ]);

    let res = await masterProxy.createProxy(singleton.address, encodedData);
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

  describe("setting up environment", () => {
    it.only("approve module on gnosis", async () => {
      const data = abi.simpleEncode(
        "enableModule(address)",
        cruizeModule.address
      );
      let hexData = "0x" + data.toString("hex");
      const signature =
        "0x000000000000000000000000" +
        signer.address.slice(2) +
        "0000000000000000000000000000000000000000000000000000000000000000" +
        "01";
      await expect(
        cruizeSafe.execTransaction(
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
        )
      )
        .emit(cruizeSafe, "EnabledModule")
        .withArgs(cruizeModule.address);
    });

    it.only("create crtokens", async () => {
      await expect(
        cruizeModule.createToken("cruzie Dai", "crdai", dai.address, 18)
      ).to.be.emit(cruizeModule, "CreateToken");

      await expect(
        cruizeModule.createToken("cruzie ETH", "crETH", ETHADDRESS, 18)
      ).to.be.emit(cruizeModule, "CreateToken");

      let crDAI = await cruizeModule.callStatic.cruizeTokens(dai.address);
      let crETH = await cruizeModule.callStatic.cruizeTokens(ETHADDRESS);
      hre.tracer.nameTags[crDAI] = "crDAI";
      hre.tracer.nameTags[crETH] = "crETH";
    });
  });

  describe("1st Round", () => {
    it.only("Deposit DAI(ERC20) token", async () => {
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

    it.only("Deposit ETH)", async () => {
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

    it.only("Initiate Withdrawal if Round is not Closed", async () => {
      await expect(cruizeModule.initiateWithdrawal(parseEther("1"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
        .withArgs(1, 1);

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );

      expect(withdrawal.round).to.be.equal(0);
      expect(withdrawal.amount).to.be.equal(BigNumber.from(0));
      expect(
        await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
      ).to.be.equal(BigNumber.from(0));
    });

    it.only("Withdraw Instantly", async () => {
      await expect(
        cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
          value: parseEther("1"),
        })
      )
        .emit(cruizeModule, "Deposit")
        .withArgs(signer.address, parseEther("1"));

      await expect(
        cruizeModule.withdrawInstantly(
          cruizeModule.address,
          parseEther("1"),
          ETHADDRESS
        )
      )
        .emit(cruizeModule, "InstantWithdraw")
        .withArgs(signer.address, parseEther("1"), 1);

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("1"));
      expect(receipt.lockedAmount).to.be.equal(parseEther("0"));
    });

    it.only("Close 1st ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(1), parseEther("1"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(2);
      expect(vault.lockedAmount).to.be.equal(parseEther("1"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
    });
  });

  /**
   * Strategy will start from 2nd round
   */
  describe("2nd round", () => {
    it.only("deposit ETH coin to contract in 2nd round", async () => {
      await expect(
        cruizeModule.deposit(ETHADDRESS, parseEther("2"), {
          value: parseEther("2"),
        })
      )
        .emit(cruizeModule, "Deposit")
        .withArgs(signer.address, parseEther("2"));
    });

    it.only("close  2nd ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(2), parseEther("3"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(3);
      expect(vault.lockedAmount).to.be.equal(parseEther("3"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
    });
  });

  describe("3rd round", () => {

    it.only("Initiate Withdraw: Throw error if balance is not enough", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("10"), ETHADDRESS)
      ).reverted
    });

    it.only("Initiate ETH Withdrawal", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("3"), ETHADDRESS)
      ).emit(cruizeModule, "InitiateWithdrawal")
      .withArgs(signer.address,ETHADDRESS,parseEther("3"));

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );
      expect(withdrawal.round).to.be.equal(3);
      expect(withdrawal.amount).to.be.equal(parseEther("3"));
      expect(
        await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
      ).to.be.equal(parseEther("3"));
    });

    it.only("close 3rd ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(3), parseEther("0"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("0"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("3"));
    });

    it.only("Complete withdrawal", async () => {
      const abiEncoder = new ethers.utils.AbiCoder();
      const data = abiEncoder.encode(
        ["address", "uint256"],
        [signer.address, parseEther("3")]
      );
      await expect(cruizeModule.withdraw(
        ETHADDRESS,
        cruizeSafe.address,
        data
      )).emit(cruizeModule,"Withdrawal")
      .withArgs(signer.address,parseEther("3"))
    });
  });

  describe("round 4th", () => {
    it.only("deposit ETH coin to contract in 4nd round to test instant withdrawal", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("10"), ETHADDRESS)
      ).emit(cruizeModule, "InitiateWithdrawal")
      .withArgs(signer.address,ETHADDRESS,parseEther("10")).reverted;

      await cruizeModule.deposit(ETHADDRESS, parseEther("2"), {
        value: parseEther("2"),
      });
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(0);
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(4);
      expect(receipt.amount).to.be.equal(parseEther("2"));
      expect(receipt.lockedAmount).to.be.equal(parseEther("0"));
    });

    it("withdrawInstantly if cruizemodule address is null", async () => {
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
  });

  describe("round 5 : testing  withdrawInstantly with  edge case", () => {
    it.only("deposit ETH coin to contract in 5 round", async () => {
      await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
        value: parseEther("1"),
      });
    });

    it.only("withdrawInstantly just after deposit if withdrawal amount is greater than deposit", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          cruizeSafe.address,
          parseEther("4"),
          ETHADDRESS
        )
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("1"), parseEther("4"));
    });

    it.only("withdrawInstantly if asset is not allowed", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          cruizeSafe.address,
          parseEther("4"),
          ethers.constants.AddressZero
        )
      ).to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
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

  describe("round 6: testing withdrawal", () => {
    it.only("initiateWithdrawal if withdrawal amount is greater than  the deposited amount", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("2000"), ETHADDRESS)
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("2"), parseEther("2000"));
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
        [signer.address, 100000000000000]
      );
      await expect(
        cruizeModule.withdraw(
          dai.address,
          cruizeSafe.address,
          "0x" + data.toString("hex")
        )
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(0, 100000000000000);
    });

    it.only("get total withdrawal amount for given asset", async () => {
      let res = await cruizeModule.vaults(dai.address);
      // console.log("total withdrawal amount for an round", res)
    });

    it.only("initiateWithdrawal for ETH ", async () => {
      await cruizeModule.initiateWithdrawal(parseEther("2"), ETHADDRESS);

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );
      expect(withdrawal.round).to.be.equal(6);
      expect(withdrawal.amount).to.be.equal(parseEther("2"));
      expect(
        await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
      ).to.be.equal(parseEther("2"));
    });

    it.only("close 6th ETH  round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
    });

    it.only("initiateWithdrawal if you already  made and withdrawal request", async () => {
      await expect(cruizeModule.initiateWithdrawal(parseEther("1"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "WithdrawalAlreadyExists")
        .withArgs(parseEther("2"));
    });

    it.only("complete withdrawal if ETH Protection Round has been closed", async () => {
      const abiEncoder = new ethers.utils.AbiCoder();
      const data = abiEncoder.encode(
        ["address", "uint256"],
        [signer.address, parseEther("2")]
      );
      await cruizeModule.withdraw(ETHADDRESS, cruizeSafe.address, data);
    });
  });

  // describe('test on edge case', () => {

  //   it.only("close 6th ETH  round", async () => {
  //     await cruizeModule.closeRound(ETHADDRESS);
  //   });

    
  // });

  

});

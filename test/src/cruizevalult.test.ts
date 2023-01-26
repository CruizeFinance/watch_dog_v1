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

      await cruizeModule.initRounds(ETHADDRESS, BigNumber.from("1"));
      await cruizeModule.initRounds(dai.address, BigNumber.from("1"));

      let crDAI = await cruizeModule.callStatic.cruizeTokens(dai.address);
      let crETH = await cruizeModule.callStatic.cruizeTokens(ETHADDRESS);
      hre.tracer.nameTags[crDAI] = "crDAI";
      hre.tracer.nameTags[crETH] = "crETH";
    });
  });

  describe("1st Round", () => {
    it("Deposit DAI(ERC20) token", async () => {
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
      await cruizeModule.deposit(ETHADDRESS, parseEther("10"), {
        value: parseEther("10"),
      });

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(1);
      expect(vault.lockedAmount).to.be.equal(0);
      expect(vault.totalPending).to.be.equal(parseEther("10"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(1)
        )
      ).to.be.equal(parseEther("1"));

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("10"));
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
      expect(withdrawal.shares).to.be.equal(BigNumber.from(0));
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(ETHADDRESS)
      ).to.be.equal(BigNumber.from(0));
    });

    it("Withdraw Instantly", async () => {
      await expect(
        cruizeModule.connect(user1).deposit(ETHADDRESS, parseEther("1"), {
          value: parseEther("1"),
        })
      )
        .emit(cruizeModule, "Deposit")
        .withArgs(user1.address, parseEther("1"));
      
        let totalShares:BigNumber = await cruizeModule.callStatic.balanceInShares(
          user1.address,
          ETHADDRESS
        )

      await expect(cruizeModule.connect(user1).withdrawInstantly(parseEther("1"), ETHADDRESS))
        .emit(cruizeModule, "InstantWithdraw")
        .withArgs(user1.address, parseEther("1"), 1);

      const receipt = await cruizeModule.callStatic.depositReceipts(
        user1.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("0"));

     expect( await cruizeModule.callStatic.balanceInShares(
      user1.address,
        ETHADDRESS
      )).to.be.equal(parseEther("1"))
      
    });

    it.only("Close 1st ETH round", async () => {
      expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("10"))

      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(1),parseEther("1"), parseEther("10"));
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      const price = await cruizeModule.callStatic.roundPricePerShare(
        ETHADDRESS,
        BigNumber.from(1)
      );
      expect(price).to.be.equal(parseEther("1"));
      expect(vault.round).to.be.equal(2);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("10"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));

      expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("10"))

    });
  });

  /**
   * Strategy will start from 2nd round
   */
  describe("2nd round", () => {
    it.only("deposit ETH", async () => {
      await expect(
        cruizeModule.deposit(ETHADDRESS, parseEther("10"), {
          value: parseEther("10"),
        })
      )
        .emit(cruizeModule, "Deposit")
        .withArgs(signer.address, parseEther("10"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(2);
      expect(vault.lockedAmount).to.be.equal(parseEther("10"));
      expect(vault.totalPending).to.be.equal(parseEther("10"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(2);
      expect(receipt.amount).to.be.equal(parseEther("10"));

      expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("20"))

    });

    it.only("Simulate 20% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("2"),
      });
    });

    it.only("close 2nd ETH round", async () => {

      expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("20"))

      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(2),parseEther("1.2"), parseEther("22"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      const price = await cruizeModule.callStatic.roundPricePerShare(
        ETHADDRESS,
        BigNumber.from(2)
      );
      expect(price).to.be.equal(parseEther("1.2"));
      expect(vault.round).to.be.equal(3);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("22"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));

      // // check user shares after round closing
      expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("18.333333333333333333"))

      expect( await cruizeModule.callStatic.balanceInAsset(
        signer.address,
        ETHADDRESS
        )).to.be.equal(parseEther("21.999999999999999999"))
  });
  });

  describe("3rd round", () => {
    it.only("Initiate Withdraw: Throw error if balance is not enough", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("30"), ETHADDRESS)
      ).reverted;
    });

    it.only("Initiate ETH Withdrawal", async () => {

      let totalShares:BigNumber = await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )
      totalShares = totalShares.div(BigNumber.from(2))
      await expect(cruizeModule.initiateWithdrawal(totalShares, ETHADDRESS))
        .emit(cruizeModule, "InitiateWithdrawal")
        .withArgs(signer.address, ETHADDRESS, totalShares);

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );
      expect(withdrawal.round).to.be.equal(3);
      expect(withdrawal.shares).to.be.equal(totalShares);
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(ETHADDRESS)
      ).to.be.equal(totalShares);

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(3);
      expect(vault.lockedAmount).to.be.equal(parseEther("22"));
    });

    it.only("close 3rd ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(3), parseEther("1.1"),parseEther("11.916666666666666667"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("11.916666666666666667"));
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("9.166666666666666666"));
    });

    it.only("Complete withdrawal", async () => {
      await expect(cruizeModule.withdraw(ETHADDRESS))
        .emit(cruizeModule, "Withdrawal")
        .withArgs(signer.address, parseEther("10.083333333333333333"));

        let totalShares:BigNumber = await cruizeModule.callStatic.balanceInShares(
          signer.address,
          ETHADDRESS
        )
        console.log(totalShares)

        expect(await cruizeModule.callStatic.balanceInAsset(
          signer.address,
          ETHADDRESS
        )).to.be.equal(parseEther("12.833333333333333341"))

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("11.916666666666666667"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));
    });
  });

  describe("4th round", () => {

    it.only("deposit ETH", async () => {
      await cruizeModule.connect(user1).deposit(ETHADDRESS, parseEther("10"), {
        value: parseEther("10"),
      });

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("11.916666666666666667"));
      expect(vault.totalPending).to.be.equal(parseEther("10"));
      console.log(await cruizeModule.callStatic.balanceInShares(
        user1.address,
        ETHADDRESS
      )) 
      expect( await cruizeModule.callStatic.balanceInShares(
        user1.address,
        ETHADDRESS
      )).to.be.equal(parseEther("9.090909090909090909"))

      const receipt = await cruizeModule.callStatic.depositReceipts(
        user1.address,
        ETHADDRESS
      )
      expect(receipt.round).to.be.equal(4);
      expect(receipt.amount).to.be.equal(parseEther("10"));
    });

    it.only("WithdrawInstantly: Throw, if amount is zero", async () => {
      await expect(cruizeModule.withdrawInstantly(parseEther("0"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroAmount")
        .withArgs(0);
    });

    it.only("WithdrawInstantly: Throw, if token address is zero-address", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          parseEther("1"),
          ethers.constants.AddressZero
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });

    it.only("Simulate 55% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("5.5"),
      });
    });

    it.only("close 4th ETH round", async () => {

      console.log(await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      ))
      // right now signer is the only participant in 4th round
      // so signer will have the shares equal to the principle + apy in the round 4th
      expect(await cruizeModule.callStatic.balanceInAsset(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("12.833333333333333341"))

      await cruizeModule.closeRound(ETHADDRESS)

      console.log(await cruizeModule.callStatic.balanceInAsset(
        signer.address,
        ETHADDRESS
      ))

      console.log(await cruizeModule.callStatic.balanceInAsset(
        user1.address,
        ETHADDRESS
      ))

      // await expect(cruizeModule.closeRound(ETHADDRESS))
      //   .emit(cruizeModule, "CloseRound")
      //   .withArgs(ETHADDRESS, BigNumber.from(4),parseEther("0.6") ,parseEther("26.500000000000000001"));

      // const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      // expect(vault.round).to.be.equal(5);
      // expect(vault.lockedAmount).to.be.equal(parseEther("2"));
      // expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
    });

    it("withdrawInstantly if round is not same", async () => {
      await expect(cruizeModule.withdrawInstantly(parseEther("1"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
        .withArgs(4, 5);
    });
  });

  describe("5th round::withdrawInstantly", () => {
    it("deposit ETH", async () => {
      await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
        value: parseEther("1"),
      });
    });

    it("withdrawInstantly just after deposit if withdrawal amount is greater than deposit", async () => {
      await expect(cruizeModule.withdrawInstantly(parseEther("4"), ETHADDRESS))
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("1"), parseEther("4"));
    });

    it("withdrawInstantly if asset is not allowed", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          parseEther("4"),
          ethers.constants.AddressZero
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });

    it("withdrawInstantly just after deposit", async () => {
      await cruizeModule.withdrawInstantly(parseEther("1"), ETHADDRESS);

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.lockedAmount).to.be.equal(parseEther("2"));
    });

    it("close 5th ETH  round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(5), parseEther("2"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(6);
      expect(vault.lockedAmount).to.be.equal(parseEther("2"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
    });
  });

  describe("6th round: Standard withdrawal", () => {
    it("initiateWithdrawal if withdrawal amount is greater than  the deposited amount", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("2000"), ETHADDRESS)
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("2"), parseEther("2000"));
    });

    it("initiateWithdrawal if  token is not allowed", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("100"), cruizeModule.address)
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(cruizeModule.address);
    });

    it("complete withdrawal when  withdrawal is not initiate", async () => {
      const data = abi.rawEncode(
        ["address", "uint256"],
        [signer.address, 100000000000000]
      );
      await expect(
        cruizeModule.withdraw(dai.address, "0x" + data.toString("hex"))
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(0, 100000000000000);
    });

    it("initiateWithdrawal for ETH ", async () => {
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

    it("close 6th ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(6), parseEther("0"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(7);
      expect(vault.lockedAmount).to.be.equal(parseEther("0"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("2"));
      const currentQueuedWithdrawalAmounts =
        await cruizeModule.callStatic.currentQueuedWithdrawalAmounts(
          ETHADDRESS
        );
      expect(currentQueuedWithdrawalAmounts).to.be.equal(parseEther("0"));
    });

    it("initiateWithdrawal if you already made withdrawal request", async () => {
      await expect(cruizeModule.initiateWithdrawal(parseEther("1"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "WithdrawalAlreadyExists")
        .withArgs(parseEther("2"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(7);
      expect(vault.lockedAmount).to.be.equal(parseEther("0"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("2"));
    });

    it("complete withdrawal if ETH Protection Round has been closed", async () => {
      const abiEncoder = new ethers.utils.AbiCoder();
      const data = abiEncoder.encode(
        ["address", "uint256"],
        [signer.address, parseEther("2")]
      );
      await cruizeModule.withdraw(ETHADDRESS, data);
    });
  });
});

/**
 * r#1 {principle:0 , deposit:10 , apy:0 , UnitPerShare:1 , AmountAfterStrategy:0 , unredeemShares:10 } start
 * crTokens = 10
 * 
*
* r#1 {principle:10 , deposit: , apy:0 , UnitPerShare:1 , AmountAfterStrategy:10 , unredeemShares:10 } close

* r#2 {principle:10 , deposit:0 , apy:20 , UnitPerShare:1 , AmountAfterStrategy:12 , pending: 0} start
* r#2 {principle:10 , deposit:10 , apy:20 , UnitPerShare:1 , AmountAfterStrategy:12 , pending: 10} deposit

crTokens = 20

 * Calculate UnitPerShare = ( AmountAfterStrategy / principle ) * rounds[n-1].UnitPerShare
 * Calculate UnitPerShare = ( 12 / 10 ) * 1
 * UnitPerShare = 1.2 = 1ETH

* r#2 {principle:10 , deposit:0 , apy:20 , UnitPerShare:1.2 , AmountAfterStrategy:12 , pending: 10} close


* r#3 {principle:22 , deposit:0 , apy:20 , UnitPerShare:? , AmountAfterStrategy:? , pending: 0} start

crTokens = ( locked - lastDepositAmount) / 1.2
          =  ( 20 - 10 ) / 1.2
          = 8.33 + lastDepsositAmount / currentRound_unitPershare
          = 8.33 + 10 / 1
          = 18.33

 * Calculate UnitPerShare = ( AmountAfterStrategy / principle ) * rounds[n-1].UnitPerShare
 * Calculate UnitPerShare = ( 26.4 / 22 ) * 1.2
 * UnitPerShare = 1.44 = 1ETH
 * 
* r#3 {principle:22 , deposit:0 , apy:20 , UnitPerShare:1.44 , AmountAfterStrategy:26.4 , pending: 0} close
crTokens = ( ( locked - lastDepositAmount) / 1.44 )+ (lastDepsositAmount / (currentRound_unitPershare/ depositTime_unitPershare ) )
  crTokens = ( locked - lastDepositAmount) / 1.44
          =  ( 20 - 10 ) / 1.44
          = 6.94 + (lastDepsositAmount / (currentRound_unitPershare/ depositTime_unitPershare ) )
          = 6.94 + (10 /  ( 1.44 / 1.2 ))
          = 6.94 + 8.33
          = 15.27 shares

* r#2 {principle:26.4 , deposit:0 , apy:20 , UnitPerShare:? , AmountAfterStrategy:? , pending: 0} start
* r#2 {principle:26.4 , deposit:10 , apy:20 , UnitPerShare:? , AmountAfterStrategy:? , pending: 10} deposit
*/

import hre, { ethers } from "hardhat";
import {
  calculatePricePerShare,
  deployCruizeContract,
  enableGnosisModule,
} from "./helpers/utils";
import { BigNumber, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "hardhat-deploy/types";
import { expect } from "chai";
import { assert } from "./helpers/assertions";
import {
  createCruizeToken,
  depositERC20,
  toBigNumber,
} from "./utilites/common.test";
import { parseEther } from "ethers/lib/utils";
describe("work flow from curize vault to cruize contract", function () {
  let signer: SignerWithAddress;
  let singleton: Contract;
  let gProxyAddress: Address;
  let cruizeSafe: Contract;
  let cruizeModule: Contract;
  let dai: Contract;
  let crETH: Contract;
  let crDAI: Contract;
  let user1: SignerWithAddress;
  let daiAddress: Address = "";
  let ETHADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  before(async () => {
    [signer, user1] = await ethers.getSigners();
    const cruizeContract = await deployCruizeContract(signer);
    cruizeSafe = cruizeContract.CruizeSafe;
    cruizeModule = cruizeContract.cruizeModule;
    gProxyAddress = cruizeContract.gProxyAddress;
    singleton = cruizeContract.singleton;
    dai = cruizeContract.dai;
    daiAddress = dai.address;
    hre.tracer.nameTags[cruizeSafe.address] = "Cruize safe";
    hre.tracer.nameTags[singleton.address] = "singleton";
    hre.tracer.nameTags[gProxyAddress as Address] = "gProxyAddress";
    hre.tracer.nameTags[cruizeModule.address] = "cruizeModule";
    hre.tracer.nameTags[user1.address] = "userOne";
    hre.tracer.nameTags[signer.address] = "singer";
  });

  describe("setting up Cruize Module and Gnosis", () => {
    it.only("approve Cruize Module from Gnosis Safe to access gnosis funds", async () => {
      const tx = await enableGnosisModule(
        cruizeSafe,
        cruizeModule.address,
        signer.address
      );
      await expect(tx)
        .emit(cruizeSafe, "EnabledModule")
        .withArgs(cruizeModule.address);
    });
  });

  describe("Creating CR tokens", () => {
    it.only("create Cr token for DAI", async () => {
      const tx = await createCruizeToken(
        "cruzie Dai",
        "crdai",
        daiAddress,
        18,
        "1000",
        cruizeModule
      );
      await expect(tx).to.be.emit(cruizeModule, "CreateToken");
    });

    it.only("create Cr token for ETH", async () => {
      const tx = await createCruizeToken(
        "cruzie ETH",
        "crETH",
        ETHADDRESS,
        18,
        "1000",
        cruizeModule
      );
      await expect(tx).to.be.emit(cruizeModule, "CreateToken");
      let crDai = await cruizeModule.callStatic.cruizeTokens(daiAddress);
      let crEth = await cruizeModule.callStatic.cruizeTokens(ETHADDRESS);
      crETH = await ethers.getContractAt("CRTokenUpgradeable", crEth);
      crDAI = await ethers.getContractAt("CRTokenUpgradeable", crDai);
      hre.tracer.nameTags[crDai] = "crDAI";
      hre.tracer.nameTags[crEth] = "crETH";
    });
  });

  describe("#Deposit in Round 1 ", () => {
    it.only("Deposit DAI(ERC20) token", async () => {
      await depositERC20(cruizeModule, dai, "10");
      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        daiAddress
      );
      assert.equal(receipt.round, 1);
      assert.equal(receipt.amount.toString(), parseEther("10"));
      assert.equal(receipt.totalDeposit.toString(), parseEther("10"));
    });
    it.only("balanceOfUser", async () => {
      const recepit = await cruizeModule.callStatic.balanceOfUser(
        daiAddress,
        signer.address
      );
      assert.equal(recepit.toString(), parseEther("0"));
    });
    it.only("Check Dai vault state", async () => {
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      assert.equal(vault.round.toString(), toBigNumber(1));
      assert.equal(vault.lockedAmount.toString(), parseEther("0"));
      assert.equal(vault.queuedWithdrawShares.toString(), parseEther("0"));
      assert.equal(vault.totalPending.toString(), parseEther("10"));
    });
    it.only("Withdraw Instantly", async () => {
      await expect(cruizeModule.deposit(daiAddress, parseEther("10")))
        .emit(cruizeModule, "Deposit")
        .withArgs(signer.address, parseEther("10"), daiAddress);
      await expect(cruizeModule.instantWithdrawal(daiAddress, parseEther("10")))
        .emit(cruizeModule, "InstantWithdrawal")
        .withArgs(signer.address, parseEther("10"), 1, daiAddress);

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        daiAddress
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("10"));
    });
    it.only("Close 1st ETH round", async () => {
      await cruizeModule.closeRound(daiAddress);
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      const roundPrice = await cruizeModule.callStatic.roundPricePerShare(
        dai.address,
        BigNumber.from(1)
      );
      const TotalSupply = await crDAI.callStatic.totalSupply();
      assert.equal(TotalSupply.toString(), parseEther("10"));
      assert.equal(vault.round, toBigNumber(2));
      assert.equal(vault.totalPending, toBigNumber(0));
      assert.equal(vault.lockedAmount.toString(), parseEther("10"));
      const vaultTotalBalance = await dai.balanceOf(cruizeSafe.address);
      const pricePerShare = await calculatePricePerShare(
        TotalSupply,
        vault.totalPending,
        vaultTotalBalance,
        18
      );
      assert.equal(roundPrice.toString(), parseEther(pricePerShare.toString()));
    });
  });

  /** ************************ Strategy will start from 2nd round ************************ **/

  describe("2nd round", async () => {
    it.only("Deposit DAI(ERC20) token", async () => {
      await depositERC20(cruizeModule, dai, "10");
      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        daiAddress
      );
      assert.equal(receipt.round, 2);
      assert.equal(receipt.amount.toString(), parseEther("10"));
      assert.equal(receipt.totalDeposit.toString(), parseEther("20"));
    });
    it.only("Check Dai vault state after 2 round start...", async () => {
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      assert.equal(vault.round, 2);
      assert.equal(vault.lockedAmount.toString(), parseEther("10"));
      assert.equal(vault.totalPending.toString(), parseEther("10"));
      assert.equal(vault.queuedWithdrawShares.toString(), parseEther("0"));
    });
    it.only("Simulate 20% APY", async () => {
      await dai.transfer(cruizeSafe.address, parseEther("2"));
    });
    it.only("close 2nd ETH round", async () => {
      await cruizeModule.closeRound(daiAddress);
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      assert.equal(vault.round, 3);
      assert.equal(vault.lockedAmount.toString(), parseEther("21.56"));
      assert.equal(vault.totalPending.toString(), parseEther("0"));
      assert.equal(vault.queuedWithdrawShares.toString(), parseEther("0"));
      expect(await crDAI.callStatic.totalSupply()).to.be.equal(
        parseEther("18.650519031141868512")
      );
      const TotalSupply = await crDAI.callStatic.totalSupply();
      const vaultTotalBalance = await dai.balanceOf(cruizeSafe.address);
      const pricePerShare = await calculatePricePerShare(
        TotalSupply,
        vault.totalPending,
        vaultTotalBalance,
        18
      );
      const roundPrice = await cruizeModule.callStatic.roundPricePerShare(
        daiAddress,
        BigNumber.from(2)
      );
      assert.equal(roundPrice.toString(), parseEther(pricePerShare.toString()));
    });
    it.only(" get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      expect(recepit).to.be.equal(parseEther("21.559999999999999999"))
    });
  });
  /**  roudn 3 deposit 10 dai locked 21.56 */
  describe("3rd round", () => {
    it.only("deposit ERC20", async () => {
      await depositERC20(cruizeModule, dai, "10");
      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        daiAddress
      );
      assert.equal(receipt.round, 3);
      assert.equal(receipt.amount.toString(), parseEther("10"));
      assert.equal(receipt.totalDeposit.toString(), parseEther("30"));
    });

    it.only("Check Dai vault state after 3 round start...", async () => {
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      assert.equal(vault.round, 3);
      assert.equal(vault.lockedAmount.toString(), parseEther("21.56"));
      assert.equal(vault.totalPending.toString(), parseEther("10"));
      assert.equal(vault.queuedWithdrawShares.toString(), parseEther("0"));
      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        daiAddress
      );
      expect(receipt.round).to.be.equal(3);
      expect(receipt.amount).to.be.equal(parseEther("10"));
      expect(receipt.unredeemedShares).to.be.equal(
        parseEther("18.650519031141868512")
      );
    });

    it.only("Initiate Withdraw: Throw error if balance is not enough", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(
          daiAddress,
          parseEther("20.650519031141868512")
        )
      )
        .revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalShare")
        .withArgs(
          parseEther("18.650519031141868512"),
          parseEther("20.650519031141868512")
        );
    });

    it.only(" get user lockedAmount", async () => {
      const recepit = await cruizeModule.callStatic.balanceOfUser(
        daiAddress,
        signer.address,
      );
      expect(toBigNumber(recepit)).to.be.equal(
        parseEther("21.559999999999999999")
      );
    });

    it.only("Initiate DAI Withdrawal in 3rd Round", async () => {
      let totalShares: any = await cruizeModule.callStatic.shareBalances(
        daiAddress,
        signer.address
      );
      totalShares = totalShares["heldByVault"];
      assert.equal(totalShares.toString(), parseEther("18.650519031141868512"));
      await expect(
        cruizeModule.initiateWithdrawal(daiAddress, parseEther("10"))
      )
        .emit(cruizeModule, "InitiateStandardWithdrawal")
        .withArgs(signer.address, daiAddress, parseEther("10"));

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        daiAddress
      );
      expect(withdrawal.round).to.be.equal(3);
      expect(withdrawal.shares).to.be.equal(parseEther("10"));
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(daiAddress)
      ).to.be.equal(parseEther("10"));

      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      expect(vault.round).to.be.equal(3);
      expect(vault.lockedAmount).to.be.equal(parseEther("21.56"));
    });

    it.only("close 3rd ETH round", async () => {
      await cruizeModule.closeRound(daiAddress);
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      expect(vault.round).to.be.equal(4);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("20"));
      expect(await crDAI.callStatic.totalSupply()).to.be.equal(
        parseEther("27.301038062283737024")
      );
      const TotalSupply = await crDAI.callStatic.totalSupply();
      const vaultTotalBalance = await dai.balanceOf(cruizeSafe.address);
      const pricePerShare = await calculatePricePerShare(
        TotalSupply,
        vault.totalPending,
        vaultTotalBalance,
        18
      );
      const roundPrice = await cruizeModule.callStatic.roundPricePerShare(
        daiAddress,
        BigNumber.from(3)
      );
      assert.equal(roundPrice.toString(), parseEther(pricePerShare.toString()));
    });
    it.only("get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      assert.equal(recepit.toString(), parseEther("19.999999999999999999"));
    });
    it.only("Complete withdrawal in 4rd Round start ", async () => {
      await expect(cruizeModule.standardWithdrawal(daiAddress))
        .emit(cruizeModule, "StandardWithdrawal")
        .withArgs(signer.address, parseEther("11.56"), daiAddress);
      expect(await crDAI.callStatic.totalSupply()).to.be.equal(
        parseEther("17.301038062283737024")
      );

      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("20"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));
    });
    /**  roudn 3 deposit 10 dai locked 21.56  initiate withdrawal of 10 shares 10*1.156 = 11.56 **/
    it.only("get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      assert.equal(recepit.toString(), parseEther("19.999999999999999999"));
    });
  });

  describe("4th round", () => {
    it.only("Simulate 20% APY", async () => {
      await dai.transfer(cruizeSafe.address, parseEther("4"));
    });

    it.only("Initiate DAI Withdrawal in 4rd Round", async () => {
      let totalShares: any = await cruizeModule.callStatic.shareBalances(
        daiAddress,
        signer.address
      );
      totalShares = totalShares["heldByVault"];

      assert.equal(
        totalShares.toString(),
        parseEther("17.301038062283737024").toString()
      );
      await expect(
        cruizeModule.initiateWithdrawal(daiAddress, parseEther("17.30"))
      )
        .emit(cruizeModule, "InitiateStandardWithdrawal")
        .withArgs(signer.address, daiAddress, parseEther("17.30"));

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        daiAddress
      );
      expect(withdrawal.round).to.be.equal(4);
      expect(withdrawal.shares).to.be.equal(parseEther("17.30"));
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(daiAddress)
      ).to.be.equal(parseEther("17.30"));

      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(
        parseEther("20.000000000000000000")
      );
    });

    it.only("close 4th ETH round", async () => {
      await depositERC20(cruizeModule, dai, "10");
      await cruizeModule.closeRound(daiAddress);
      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      expect(vault.round).to.be.equal(5);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("10.0013872"));
      expect(await crDAI.callStatic.totalSupply()).to.be.equal(
        parseEther("24.784186013098502172")
      );

      const TotalSupply = await crDAI.callStatic.totalSupply();
      const vaultTotalBalance = await dai.balanceOf(cruizeSafe.address);
      const pricePerShare = await calculatePricePerShare(
        TotalSupply,
        vault.totalPending,
        vaultTotalBalance,
        18
      );
      const roundPrice = await cruizeModule.callStatic.roundPricePerShare(
        daiAddress,
        BigNumber.from(4)
      );
      assert.equal(roundPrice.toString(), parseEther("1.336336"));
    });

    it.only("get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      expect(recepit).to.be.equal(parseEther("10.001387199999999998"))
      // assert.equal(recepit.toString(), parseEther("21.56"));
    });

    it.only("Complete withdrawal in 5rd Round  start ", async () => {
      await expect(cruizeModule.standardWithdrawal(daiAddress))
        .emit(cruizeModule, "StandardWithdrawal")
        .withArgs(
          signer.address,
          parseEther("23.118612800000000000"),
          daiAddress
        );
      expect(await crDAI.callStatic.totalSupply()).to.be.equal(
        parseEther("7.484186013098502172")
      );

      const vault = await cruizeModule.callStatic.vaults(daiAddress);
      expect(vault.round).to.be.equal(5);
      expect(vault.lockedAmount).to.be.equal(parseEther("10.0013872"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));
    });
    it.only("WithdrawInstantly: Throw, if amount is zero", async () => {
      await expect(cruizeModule.instantWithdrawal(daiAddress, parseEther("0")))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroValue")
        .withArgs(0);
    });

    it.only("WithdrawInstantly: Throw, if token address is zero-address", async () => {
      await expect(
        cruizeModule.instantWithdrawal(
          ethers.constants.AddressZero,
          parseEther("1")
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });
    it.only("get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      expect(recepit).to.be.equal(parseEther("10.001387199999999998"))
      // assert.equal(recepit.toString(), parseEther("21.56"));
    });
  });


  describe("Round 5th", () => {
    it.only("instantWithdraw if round is not same", async () => {
      await expect(cruizeModule.instantWithdrawal(daiAddress, parseEther("10")))
        .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
        .withArgs(4, 5);
    });

    it.only("instantWithdraw just after deposit if withdrawal amount is greater than deposit", async () => {
      await depositERC20(cruizeModule, dai, "10");
      await expect(cruizeModule.instantWithdrawal(daiAddress, parseEther("50")))
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("10"), parseEther("50"));
    });

    it.only("instantWithdraw if asset is not allowed", async () => {
      await expect(
        cruizeModule.instantWithdrawal(
          ethers.constants.AddressZero,
          parseEther("4")
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });
    it.only("initiateWithdrawal if withdrawal amount is greater than  the deposited amount", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(ETHADDRESS, parseEther("2000"))
      )
        .to.be.revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalShare")
        .withArgs(parseEther("0"), parseEther("2000"));
    });
    it.only("complete withdrawal when  withdrawal is not initiate", async () => {
      await expect(
        cruizeModule.standardWithdrawal(daiAddress)
      ).to.be.revertedWithCustomError(cruizeModule, "ZeroWithdrawalShare");
    });
    it.only("get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      expect(recepit).to.be.equal(parseEther("10.001387199999999998"))
      // assert.equal(recepit.toString(), parseEther("21.56"));
    });  
    it.only("close 5th round ", async () => {
      await cruizeModule.closeRound(daiAddress);
      const roundPrice = await cruizeModule.callStatic.roundPricePerShare(
        daiAddress,
        BigNumber.from(5)
      );
      // assert.equal(roundPrice.toString(), parseEther("1.336336"));
    });
    
    it.only("initiateWithdrawal", async () => {
      await cruizeModule.initiateWithdrawal(daiAddress, parseEther("10"));
    });
    // it.only("Simulate 20% APY", async () => {
    //   await dai.transfer(cruizeSafe.address, parseEther("4"));
    // });
    it.only("get user lockedAmount", async () => {
      const recepit = await cruizeModule.balanceOfUser(
        daiAddress,
        signer.address,
      );
      expect(recepit).to.be.equal(parseEther("6.638027199999999997"))
      // assert.equal(recepit.toString(), parseEther("21.56"));
    });  
  });
 
  describe("testing setter and getters", () => {
    it.only("set valut Cap", async () => {
      await expect(cruizeModule.setCap(daiAddress, parseEther("10")))
        .to.emit(cruizeModule, "CapSet")
        .withArgs(daiAddress,parseEther("1000"), parseEther("10"));
    });
    it.only("set valut Cap is vaule is zero", async () => {
      await expect(cruizeModule.setCap(daiAddress, parseEther("0")))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroValue")
        .withArgs("0");
    });
    it.only("set valut Cap address is null", async () => {
      await expect(
        cruizeModule.setCap(ethers.constants.AddressZero, parseEther("0"))
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });
    it.only("set setFeeRecipient", async () => {
      await expect(cruizeModule.setFeeRecipient(user1.address));
    });
    it.only("set setFeeRecipient address is null", async () => {
      await expect(cruizeModule.setFeeRecipient(ethers.constants.AddressZero))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroAddress")
        .withArgs(ethers.constants.AddressZero);
    });

    it.only("set setManagementFee with 0 value", async () => {
      await expect(cruizeModule.setManagementFee(parseEther("0")))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroValue")
        .withArgs("0");
    });
    it.only("set setManagementFee", async () => {
      await expect(cruizeModule.setManagementFee(parseEther("20")))
        .to.be.emit(cruizeModule, "ManagementFeeSet")
        .withArgs(parseEther("2"), parseEther("20"));
    });
    it.only("set setPerformanceFee with 0 value", async () => {
      await expect(cruizeModule.setPerformanceFee(parseEther("0")))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroValue")
        .withArgs("0");
    });
    it.only("set setPerformanceFee ", async () => {
      await expect(cruizeModule.setPerformanceFee(parseEther("20")))
        .to.be.emit(cruizeModule, "PerformanceFeeSet")
        .withArgs(parseEther("10"), parseEther("20"));
    });
  });
});

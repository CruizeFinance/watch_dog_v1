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
      expect(withdrawal.amount).to.be.equal(BigNumber.from(0));
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(ETHADDRESS)
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

      await expect(cruizeModule.withdrawInstantly(parseEther("1"), ETHADDRESS))
        .emit(cruizeModule, "InstantWithdraw")
        .withArgs(signer.address, parseEther("1"), 1);

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("10"));

     expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("10"))
      
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

    it.only("Simulate 10% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("2"),
      });
    });

    it.only("close  2nd ETH round", async () => {

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

      // check user shares after round closing
      expect( await cruizeModule.callStatic.balanceInShares(
        signer.address,
        ETHADDRESS
      )).to.be.equal(parseEther("16.666666666666666666"))

        console.log(await cruizeModule.callStatic.balanceInAsset(
          signer.address,
          ETHADDRESS
          ));
      // expect( await cruizeModule.callStatic.balanceInAsset(
      //   signer.address,
      //   ETHADDRESS
      //   )).to.be.equal(parseEther("12"))
  });
  });

  describe("3rd round", () => {
    it("Initiate Withdraw: Throw error if balance is not enough", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("30"), ETHADDRESS)
      ).reverted;
    });

    it("Initiate ETH Withdrawal", async () => {
      await expect(cruizeModule.initiateWithdrawal(parseEther(""), ETHADDRESS))
        .emit(cruizeModule, "InitiateWithdrawal")
        .withArgs(signer.address, ETHADDRESS, parseEther("3"));

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );
      expect(withdrawal.round).to.be.equal(3);
      expect(withdrawal.amount).to.be.equal(parseEther("3"));
      expect(
        await cruizeModule.currentQueuedWithdrawalAmounts(ETHADDRESS)
      ).to.be.equal(parseEther("3"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(3);
      expect(vault.lockedAmount).to.be.equal(parseEther("3"));
    });

    it("close 3rd ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(3), parseEther("0"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("0"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("3"));
    });

    it("Complete withdrawal", async () => {
      const abiEncoder = new ethers.utils.AbiCoder();
      const data = abiEncoder.encode(
        ["address", "uint256"],
        [signer.address, parseEther("3")]
      );
      await expect(cruizeModule.withdraw(ETHADDRESS, data))
        .emit(cruizeModule, "Withdrawal")
        .withArgs(signer.address, parseEther("3"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(parseEther("0"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
    });
  });

  describe("4th round", () => {
    it("deposit ETH", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(parseEther("10"), ETHADDRESS)
      )
        .emit(cruizeModule, "InitiateWithdrawal")
        .withArgs(signer.address, ETHADDRESS, parseEther("10")).reverted;

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

    it("WithdrawInstantly: Throw, if amount is zero", async () => {
      await expect(cruizeModule.withdrawInstantly(parseEther("0"), ETHADDRESS))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroAmount")
        .withArgs(0);
    });

    it("WithdrawInstantly: Throw, if token address is zero-address", async () => {
      await expect(
        cruizeModule.withdrawInstantly(
          parseEther("1"),
          ethers.constants.AddressZero
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });

    it("close 4th ETH round", async () => {
      await expect(cruizeModule.closeRound(ETHADDRESS))
        .emit(cruizeModule, "CloseRound")
        .withArgs(ETHADDRESS, BigNumber.from(4), parseEther("2"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(5);
      expect(vault.lockedAmount).to.be.equal(parseEther("2"));
      expect(vault.queuedWithdrawalAmount).to.be.equal(parseEther("0"));
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
 * r#1 {principle:0 , deposit:10 , apy:0 , UnitPerShare:1 , AmountAfterStrategy:0 , unredeemShares:10 } user0 = 10 shares/crTokens
 * totalAPY -  userDepositAPY *  2 =  deposit
 * 0 - 0 
 *
 * r#2 {principle:10 , deposit:0 , apy:20% , apywheuserDeposit =  UnitPerShare:1.2 , AmountAfterStrategy:12 } nexLockedAmount = totalBalance(ETH) - convertToETH( queuedwithdrawalShares )
 * deposit 10eth -> 10 shares
 * 20 shares
 * 20/1 = 20
 * 20 - 10
 * 10 locked
 * pending 10
 * totalAPY -  userDepositAPY *  2 =  deposit
 * 
 * Calculate UnitPerShare = ( AmountAfterStrategy / principle ) * rounds[n-1].UnitPerShare
 * Calculate UnitPerShare = ( 12 / 10 ) * 1
 * UnitPerShare = 1.2 = 1ETH
 * r#2  {principle:12 , deposit:0 , apy:10% , UnitPerShare:1.2 , AmountAfterStrategy:13.2 , queuedwithdraw:0}
 * round closed 
 * r#3  {principle:13.2 , deposit:10 , apy:10% , UnitPerShare:1.5, AmountAfterStrategy: 25.3 , queuedwithdraw:0}
 * 20 - 0 * 10 * 2 = 12
 * 2.2 - 1 * 20  % 1.2
 * 22 / 1.2 =  18.33
 * userShares = 10ETH / 1.2 = 8.33shares/crToken
 * 8.33 + 10 = 18.33 shares/crToken
 * 18.33 * 1.2 = 21.181ETH
 * 
 * 1 * 1.2 = 1.2ETH
 * 
 * 
 *
 * r#4 {principle:25.2 , deposit:10 , apy:10% , UnitPerShare: ?  , AmountAfterStrategy: ?} 100/ 1.24 = 80 > should get 105~
 * 21.18 * 2.181 = 
 * 
 * 
 * Calculate UnitPerShare = ( AmountAfterStrategy / principle ) * rounds[n-1].UnitPerShare
 * Calculate UnitPerShare = ( 125 / 112 ) * 1.2
 * UnitPerShare = 1.25
 *
 *  * r#4 {principle:225 , deposit:0 , apy:5% , UnitPerShare:1.31 , AmountAfterStrategy:236 }
 * Calculate UnitPerShare = ( AmountAfterStrategy / principle ) * rounds[n-1].UnitPerShare
 * Calculate UnitPerShare = ( 236 / 225 ) * 1.25
 * UnitPerShare = 1.31
 *
 * withdraw 80 shares = 80*1.31 = 104.8 ETH
 * 
 *
 */
/**
 * r#1 {principle:0 , deposit:10 ,totalamount = 10  apy:0 , UnitPerShare:1 , AmountAfterStrategy:0 , unredeemShares:10,apywhenuserdeposit: 0  } user0 = 10 shares/crTokens
(  totalapy - apywhenuserdeposit) totalamount  * totalamount / 100 =  userapy 
 * r#2 {principle:12 , deposit:10 ,totalamount = 22, apy:20% , totaluseramount = 10 , UnitPerShare:1.2 , AmountAfterStrategy:12 , unredeemShares:10,apywhenuserdeposit: 20%  } user0 = 10 shares/crTokens
 
(  totalapy - apywhenuserdeposit) totalamount  * totalamount / 100 =  userapy 
  20 * 10 / 100 = 2 , 12  + 10 = 22

 * r#3 {principle:22 , deposit:, totaluseramount = 22, apy:10% , UnitPerShare:1.2 , AmountAfterStrategy:24.2 , unredeemShares:10,apywhenuserdeposit: 10%  } user0 = 10 shares/crTokens
 * r#4 {principle:24.2 , deposit10:, totaluseramount = 34.2, apy:10% , UnitPerShare:1.2 , AmountAfterStrategy: , unredeemShares:10,apywhenuserdeposit: 10%  } user0 = 10 shares/crTokens
  totalapy -  apywhenuserdeposit  * totalamount / 100 =  userapy 
  30 - 20 * 22 / 100   = 2.2
  totalamount +  2.2  = 24.2  +  10 = 34.2 
  
reset parsent = 100% 
apy = 20%  apy = 10%, 
1 * 988 / 100 = 9.98 
1------------2----------3------------4
   ta = 20    ta = 30  
 */
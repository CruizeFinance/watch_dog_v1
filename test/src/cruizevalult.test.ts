import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import hre, { ethers } from "hardhat";
import { DepositERC20, deployContracts } from "./utilites/common.test";
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
  let crETH: Contract;
  let crDAI: Contract;
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
      "contracts/gnosis-safe/safe.sol:GnosisSafe",
      gProxyAddress as Address,
      signer
    );

    const CRUIZEMODULE = await ethers.getContractFactory("Cruize", signer);

    cruizeModule = await CRUIZEMODULE.deploy(
      signer.address,
      gProxyAddress,
      crContract.address,
      parseEther("10")
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
      ).emit(cruizeSafe, "EnabledModule")
        .withArgs(cruizeModule.address);
    });

    it.only("create crtokens", async () => {
      await expect(
        cruizeModule.createToken(
          "cruzie Dai",
          "crdai",
          dai.address,
          18,
          parseEther("1000")
        )
      ).to.be.emit(cruizeModule, "CreateToken");

      await expect(
        cruizeModule.createToken(
          "cruzie ETH",
          "crETH",
          ETHADDRESS,
          18,
          parseEther("1000")
        )
      ).to.be.emit(cruizeModule, "CreateToken");

      await cruizeModule.initRounds(ETHADDRESS, BigNumber.from("1"));
      await cruizeModule.initRounds(dai.address, BigNumber.from("1"));

      let crDai = await cruizeModule.callStatic.cruizeTokens(dai.address);
      let crEth = await cruizeModule.callStatic.cruizeTokens(ETHADDRESS);

      crETH = await ethers.getContractAt("CRTokenUpgradeable", crEth);
      crDAI = await ethers.getContractAt("CRTokenUpgradeable", crDai);
      hre.tracer.nameTags[crDai] = "crDAI";
      hre.tracer.nameTags[crEth] = "crETH";
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
      ).to.be.equal(BigNumber.from(1));

      const receipt = await cruizeModule.callStatic.depositReceipts(
        signer.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("10"));
    });

    it("Initiate Withdrawal if Round is not Closed", async () => {
      await expect(cruizeModule.initiateWithdrawal(ETHADDRESS,parseEther("1")))
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

      let totalShares: BigNumber =
        await cruizeModule.callStatic.balanceInShares(
          user1.address,
          ETHADDRESS
        );

      await expect(
        cruizeModule
          .connect(user1)
          .instantWithdraw(ETHADDRESS,parseEther("1"))
      )
        .emit(cruizeModule, "InstantWithdraw")
        .withArgs(user1.address, parseEther("1"), 1);

      const receipt = await cruizeModule.callStatic.depositReceipts(
        user1.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(1);
      expect(receipt.amount).to.be.equal(parseEther("0"));

      expect(
        await cruizeModule.callStatic.balanceInShares(user1.address, ETHADDRESS)
      ).to.be.equal(parseEther("1"));
    });

    it.only("Close 1st ETH round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(1)
        )
      ).to.be.equal(parseEther("1"));
      expect(vault.round).to.be.equal(2);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("10"));
      expect(await crETH.callStatic.totalSupply()).to.be.equal(
        parseEther("10")
      );
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
        .withArgs(signer.address, parseEther("10"), ETHADDRESS);

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(2);
      expect(vault.lockedAmount).to.be.equal(parseEther("10"));
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
      expect(receipt.round).to.be.equal(2);
      expect(receipt.amount).to.be.equal(parseEther("10"));
      expect(receipt.unredeemedShares).to.be.equal(parseEther("10"));
    });

    it.only("Simulate 20% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("2"),
      });
    });

    it.only("close 2nd ETH round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(2)
        )
      ).to.be.equal(parseEther("1.18"));
      expect(vault.round).to.be.equal(3);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("21.8"));
      expect(await crETH.callStatic.totalSupply()).to.be.equal(
        parseEther("18.474576271186440677")
      );
    });
    it.only("get user balance",async()=>{
      const vault = await cruizeModule.callStatic.getUserLockedAmount(signer.address,ETHADDRESS);
      console.log(vault);
    })
  });
  
  describe("3rd round", () => {
    it.only("deposit ETH", async () => {
      await expect(
        cruizeModule.connect(user1).deposit(ETHADDRESS, parseEther("10"), {
          value: parseEther("10"),
        })
      )
        .emit(cruizeModule, "Deposit")
        .withArgs(user1.address, parseEther("10"), ETHADDRESS);

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(3);
      expect(vault.lockedAmount).to.be.equal(parseEther("21.8"));
      expect(vault.totalPending).to.be.equal(parseEther("10"));
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));
      const receipt = await cruizeModule.callStatic.depositReceipts(
        user1.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(3);
      expect(receipt.amount).to.be.equal(parseEther("10"));
      expect(receipt.unredeemedShares).to.be.equal(parseEther("0"));
    });

    it.only("Simulate 50% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("10.9"),
      });
    });

    it("Initiate Withdraw: Throw error if balance is not enough", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(ETHADDRESS,parseEther("30"))
      ).reverted;
    });

    it("Initiate ETH Withdrawal", async () => {
      let totalShares: BigNumber =
        await cruizeModule.callStatic.balanceInShares(
          signer.address,
          ETHADDRESS
        );
      totalShares = totalShares.div(BigNumber.from(2));
      await expect(cruizeModule.initiateWithdrawal(ETHADDRESS,totalShares))
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
      await cruizeModule.closeRound(ETHADDRESS);
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(3)
        )
      ).to.be.equal(parseEther("1.711"));
      expect(vault.round).to.be.equal(4);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("41.61"));
      expect(await crETH.callStatic.totalSupply()).to.be.equal(
        parseEther("24.319111630625365282")
      );
    });

    it("Complete withdrawal", async () => {
      await expect(cruizeModule.standardWithdraw(ETHADDRESS))
        .emit(cruizeModule, "Withdrawal")
        .withArgs(signer.address, parseEther("10.083333333333333333"));

      let totalShares: BigNumber =
        await cruizeModule.callStatic.balanceInShares(
          signer.address,
          ETHADDRESS
        );
      console.log(totalShares);

      expect(
        await cruizeModule.callStatic.balanceInAsset(signer.address, ETHADDRESS)
      ).to.be.equal(parseEther("12.833333333333333341"));

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(
        parseEther("11.916666666666666667")
      );
      expect(vault.queuedWithdrawShares).to.be.equal(parseEther("0"));
    });
  });

  describe("4th round", () => {
    it.only("Simulate 10% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("4.116"),
      });
    });

    it("deposit ETH", async () => {
      await cruizeModule.connect(user1).deposit(ETHADDRESS, parseEther("10"), {
        value: parseEther("10"),
      });

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(4);
      expect(vault.lockedAmount).to.be.equal(
        parseEther("11.916666666666666667")
      );
      expect(vault.totalPending).to.be.equal(parseEther("10"));
      console.log(
        await cruizeModule.callStatic.balanceInShares(user1.address, ETHADDRESS)
      );
      expect(
        await cruizeModule.callStatic.balanceInShares(user1.address, ETHADDRESS)
      ).to.be.equal(parseEther("9.090909090909090909"));

      const receipt = await cruizeModule.callStatic.depositReceipts(
        user1.address,
        ETHADDRESS
      );
      expect(receipt.round).to.be.equal(4);
      expect(receipt.amount).to.be.equal(parseEther("10"));
    });

    it("WithdrawInstantly: Throw, if amount is zero", async () => {
      await expect(cruizeModule.instantWithdraw(ETHADDRESS,parseEther("0")))
        .to.be.revertedWithCustomError(cruizeModule, "ZeroAmount")
        .withArgs(0);
    });

    it("WithdrawInstantly: Throw, if token address is zero-address", async () => {
      await expect(
        cruizeModule.instantWithdraw(
          ethers.constants.AddressZero,
          parseEther("1")
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });

    it("Simulate 55% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("5.5"),
      });
    });

    it.only("close 4th ETH round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(4)
        )
      ).to.be.equal(parseEther("1.863324643114635904"));
      expect(vault.round).to.be.equal(5);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(parseEther("45.3144"));
      expect(await crETH.callStatic.totalSupply()).to.be.equal(
        parseEther("24.319111630625365282")
      );
    });

    it("instantWithdraw if round is not same", async () => {
      await expect(cruizeModule.instantWithdraw(ETHADDRESS,parseEther("1")))
        .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
        .withArgs(4, 5);
    });
  });

  describe("5th round", () => {
    it.only("Simulate 10% APY", async () => {
      await signer.sendTransaction({
        to: cruizeSafe.address,
        value: parseEther("4.73"),
      });
    });

    it.only("Initiate ETH Withdrawal", async () => {
      let shares = await cruizeModule.callStatic.shareBalances(
        ETHADDRESS,
        user1.address
      );
      let totalShares = BigNumber.from(shares.heldByVault);
      await expect(
        cruizeModule.connect(user1).initiateWithdrawal(ETHADDRESS,totalShares)
      )
        .emit(cruizeModule, "initiateStandardWithdrawal")
        .withArgs(user1.address, ETHADDRESS, totalShares);

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        user1.address,
        ETHADDRESS
      );
      expect(withdrawal.round).to.be.equal(5);
      expect(withdrawal.shares).to.be.equal(totalShares);
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(ETHADDRESS)
      ).to.be.equal(totalShares);

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(5);
      expect(vault.lockedAmount).to.be.equal(parseEther("45.3144"));
    });

    it.only("close 5th ETH round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(5)
        )
      ).to.be.equal(parseEther("2.038372155731795241"));
      expect(vault.round).to.be.equal(6);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(
        parseEther("37.658061860129776501")
      );
      expect(await crETH.callStatic.totalSupply()).to.be.equal(
        parseEther("24.319111630625365282")
      );
    });
    it("transferFromSafe", async () => {
      const vault = await cruizeModule.transferFromSafe(
        signer.address,
        ETHADDRESS,
        parseEther("10")
      );
    });

    it("deposit ETH", async () => {
      await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
        value: parseEther("1"),
      });
    });

    it("instantWithdraw just after deposit if withdrawal amount is greater than deposit", async () => {
      await expect(cruizeModule.instantWithdraw(ETHADDRESS,parseEther("4")))
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("1"), parseEther("4"));
    });

    it("instantWithdraw if asset is not allowed", async () => {
      await expect(
        cruizeModule.instantWithdraw(
          ethers.constants.AddressZero,
          parseEther("4")
        )
      )
        .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
        .withArgs(ethers.constants.AddressZero);
    });

    it("instantWithdraw just after deposit", async () => {
      await cruizeModule.instantWithdraw(parseEther("1"), ETHADDRESS);

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

  describe("6th round", () => {
    it("initiateWithdrawal if withdrawal amount is greater than  the deposited amount", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(ETHADDRESS,parseEther("2000"))
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(parseEther("2"), parseEther("2000"));
    });

    it("initiateWithdrawal if  token is not allowed", async () => {
      await expect(
        cruizeModule.initiateWithdrawal(cruizeModule.address,parseEther("100"))
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
        cruizeModule.standardWithdraw(dai.address, "0x" + data.toString("hex"))
      )
        .to.be.revertedWithCustomError(
          cruizeModule,
          "NotEnoughWithdrawalBalance"
        )
        .withArgs(0, 100000000000000);
    });

    it.only("initiateWithdrawal for ETH ", async () => {
      let shares = await cruizeModule.callStatic.shareBalances(
        ETHADDRESS,
        signer.address
      );
      let totalShares = BigNumber.from(shares.heldByVault);
      await cruizeModule.initiateWithdrawal(ETHADDRESS,totalShares);

      const withdrawal = await cruizeModule.callStatic.withdrawals(
        signer.address,
        ETHADDRESS
      );
      expect(withdrawal.round).to.be.equal(6);
      expect(withdrawal.shares).to.be.equal(totalShares);
      expect(
        await cruizeModule.currentQueuedWithdrawalShares(ETHADDRESS)
      ).to.be.equal(totalShares);

      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(vault.round).to.be.equal(6);
      expect(vault.lockedAmount).to.be.equal(
        parseEther("37.658061860129776501")
      );
    });

    it.only("close 6th ETH round", async () => {
      await cruizeModule.closeRound(ETHADDRESS);
      const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
      expect(
        await cruizeModule.callStatic.roundPricePerShare(
          ETHADDRESS,
          BigNumber.from(6)
        )
      ).to.be.equal(parseEther("1.973887114424240821"));
      expect(vault.round).to.be.equal(7);
      expect(vault.totalPending).to.be.equal(parseEther("0"));
      expect(vault.lockedAmount).to.be.equal(BigNumber.from(4));
      expect(await crETH.callStatic.totalSupply()).to.be.equal(
        parseEther("24.319111630625365282")
      );
    });

    it("initiateWithdrawal if you already made withdrawal request", async () => {
      await expect(cruizeModule.initiateWithdrawal(ETHADDRESS,parseEther("1")))
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
      await cruizeModule.standardWithdraw(ETHADDRESS, data);
    });
  });

  describe("7th round", () => {
    it.only("user:1 complete withdrawal", async () => {
      await cruizeModule.connect(user1).standardWithdraw(ETHADDRESS);
      await cruizeModule.connect(signer).standardWithdraw(ETHADDRESS);
    });
  });
});

/**
 * 1  deposit 10 ETH , total amount 10 , minted share = 10 
 
 * 2 round deposit 10 Eth , total amount 21.8 , apy = 10% vault fee 0.2
 * 11.8  - 10 / 10 = 1.8 
 * 2 round closed 
 * 3rd round ingoing,  total 30 ,deposit 10 ETH , apy 50% , valut fee 1.09
 * 
 * 
 */

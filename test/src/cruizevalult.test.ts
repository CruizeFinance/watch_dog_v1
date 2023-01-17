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


describe("work flow form curize vault to cruize contract", function () {
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
      "contracts/gnosis-safe/proxy.sol:GnosisSafeProxyFactory",
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
      "GnosisSafe",
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

  it.only("deposit ETH coin to contract", async () => {
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

  it.only("withdrawInstantly if cruizemodule address is null", async () => {
    await expect(
      cruizeModule.withdrawInstantly(
        ethers.constants.AddressZero,
        parseEther("1"),
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

  it.only("close 1st ETH Deposit  round", async () => {
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
      .withArgs(1, 2);
  });

  it.only("withdrawInstantly just after deposit", async () => {
    const vault = await cruizeModule.callStatic.vaults(ETHADDRESS);
    expect(vault.lockedAmount).to.be.equal(parseEther("1"));

    await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
      value: parseEther("1"),
    });

    await cruizeModule.withdrawInstantly(
      cruizeSafe.address,
      parseEther("1"),
      ETHADDRESS
    );
  });

  it.only("withdrawInstantly just after deposit if withdrawal amount is greater then deposit", async () => {
    await cruizeModule.deposit(ETHADDRESS, parseEther("3"), {
      value: parseEther("3"),
    });
    await expect(
      cruizeModule.withdrawInstantly(
        cruizeSafe.address,
        parseEther("4"),
        ETHADDRESS
      )
    )
      .to.be.revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalBalance")
      .withArgs(parseEther("3"), parseEther("4"));
  });

  it.only("withdrawInstantly if asset is not allowed", async () => {
    await cruizeModule.deposit(ETHADDRESS, parseEther("1"), {
      value: parseEther("3"),
    });
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

  it.only("initiateWithdrawal if  1st deposit Round is not Closed", async () => {
    await expect(cruizeModule.initiateWithdrawal(parseEther("10"), dai.address))
      .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
      .withArgs(1, 1);
    const withdrawal = await cruizeModule.callStatic.withdrawals(
      signer.address,
      dai.address
    );
    console.log(withdrawal);
    expect(withdrawal.round).to.be.equal(0);
    expect(withdrawal.amount).to.be.equal(BigNumber.from(0));
    expect(
      await cruizeModule.currentQueuedWithdrawalAmounts(dai.address)
    ).to.be.equal(BigNumber.from(0));
  });

  it.only("initiateWithdrawal when 1st Dai deposit Round is not  Closed", async () => {
    const withdrawal = await cruizeModule.callStatic.withdrawals(
      signer.address,
      dai.address
    );
    console.log(withdrawal);
    expect(withdrawal.round).to.be.equal(0);
    expect(withdrawal.amount).to.be.equal(BigNumber.from(0));
    await expect(
      cruizeModule.initiateWithdrawal(parseEther("2000"), dai.address)
    )
      .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
      .withArgs(1, 1);
  });

  it.only("close 1st Deposit Round  for Dai", async () => {
    await cruizeModule.closeRound(dai.address);
  });

  it.only("initiateWithdrawal with wrong withdrawal amount", async () => {
    await expect(
      cruizeModule.initiateWithdrawal(parseEther("2000"), dai.address)
    )
      .to.be.revertedWithCustomError(cruizeModule, "NotEnoughWithdrawalBalance")
      .withArgs(parseEther("10"), parseEther("2000"));
  });

  it.only("initiateWithdrawal if  token is not allowed", async () => {
    await expect(
      cruizeModule.initiateWithdrawal(parseEther("100"), cruizeModule.address)
    )
      .to.be.revertedWithCustomError(cruizeModule, "AssetNotAllowed")
      .withArgs(cruizeModule.address);
  });

  it.only("initiateWithdrawal if withdrawal amount is greater then  the deposited amount", async () => {
    cruizeModule.initiateWithdrawal(parseEther("100"), dai.address);
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

  it.only("initiateWithdrawal if Dai 1st deposit Round is  Closed", async () => {
    await cruizeModule.initiateWithdrawal(parseEther("10"), dai.address);

    const withdrawal = await cruizeModule.callStatic.withdrawals(
      signer.address,
      dai.address
    );
    console.log(withdrawal);
    expect(withdrawal.round).to.be.equal(2);
    expect(withdrawal.amount).to.be.equal(parseEther("10"));
    expect(
      await cruizeModule.currentQueuedWithdrawalAmounts(dai.address)
    ).to.be.equal(parseEther("10"));
  });

  it.only("get total withdrawal amount for given asset", async () => {
    let res = await cruizeModule.vaults(dai.address);
    // console.log("total withdrawal amount for an round", res)
  });

  it.only("complete withdrawal if Dai 1st Protection is Round not closed", async () => {
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
      .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
      .withArgs(2, 2);
  });

  it.only("withdrawinstantly in the 1st  Protection round of Dai ", async () => {
    const vault = await cruizeModule.callStatic.vaults(dai.address);
    expect(vault.lockedAmount).to.be.equal(parseEther("10"));
    await expect(
      cruizeModule.withdrawInstantly(
        cruizeSafe.address,
        parseEther("10"),
        dai.address
      )
    )
      .to.be.revertedWithCustomError(cruizeModule, "InvalidWithdrawalRound")
      .withArgs(1, 2);
  });
  
  it.only("close Dai 1st Protection Round", async () => {
    await cruizeModule.closeRound(dai.address);
  });

  it.only("initiateWithdrawal if you already  made and withdrawal request", async () => {
    await expect(cruizeModule.initiateWithdrawal(parseEther("10"), dai.address))
      .to.be.revertedWithCustomError(cruizeModule, "WithdrawalAlreadyExists")
      .withArgs(parseEther("10"));
  });

  it.only("complete withdrawal if Dai 1st Protection Round has been closed", async () => {
    const data = abi.rawEncode(
      ["address", "uint256"],
      [ signer.address, 100000000000000]
    );
    await cruizeModule.withdraw(
      dai.address,
      cruizeSafe.address,
      "0x" + data.toString("hex")
    );
  });
});

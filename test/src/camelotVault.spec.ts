import hre, { ethers } from "hardhat";
import { BigNumber, constants, Contract, ContractFunction } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseEther } from "ethers/lib/utils";
import { Impersonate } from "./utilites/common.test";

const NFTPOOL = "0x6BC938abA940fB828D39Daa23A94dfc522120C11";
const ROUTER = "0xc873fEcbd354f5A56E00E710B90EF4201db2448d";
const USDC = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
const WETH = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
const CAMELOT_LP = "0x84652bb2539513BAf36e225c930Fdd8eaa63CE27";
const EXTERNAL_ACCOUNT = "0x62B8e137ee87Ab3CaEB2FEA3B88D04abeA7C5579";

describe("work flow from curize vault to cruize contract", function () {
  let nftPool: Contract;
  let router: Contract;
  let usdc: Contract;
  let weth: Contract;
  let lp: Contract;
  let crCamelotVault: Contract;
  let signer: SignerWithAddress;
  let deployer: SignerWithAddress;
  let externalUser: SignerWithAddress;
  let userTokenId: BigNumber;

  before(async () => {
    [signer, deployer] = await ethers.getSigners();
    externalUser = await Impersonate(EXTERNAL_ACCOUNT);

    const CamelotVault = await ethers.getContractFactory(
      "CamelotVault",
      deployer
    );
    crCamelotVault = await CamelotVault.deploy();

    nftPool = await ethers.getContractAt("INftPool", NFTPOOL, deployer);
    router = await ethers.getContractAt("ICamelotRouter", ROUTER, deployer);

    usdc = await ethers.getContractAt(
      "contracts/gnosis-safe/safe.sol:IERC20",
      USDC,
      deployer
    );

    weth = await ethers.getContractAt(
      "contracts/gnosis-safe/safe.sol:IERC20",
      WETH,
      deployer
    );

    lp = await ethers.getContractAt(
      "contracts/gnosis-safe/safe.sol:IERC20",
      CAMELOT_LP,
      deployer
    );

    hre.tracer.nameTags[crCamelotVault.address] = "crCruizeCamelotVault";
    hre.tracer.nameTags[EXTERNAL_ACCOUNT] = "EXTERNAL-ACCOUNT";
    hre.tracer.nameTags[deployer.address] = "DEPLOYER";
    hre.tracer.nameTags[signer.address] = "SIGNER";
    hre.tracer.nameTags[CAMELOT_LP] = "CAMELOT-LP";
    hre.tracer.nameTags[ROUTER] = "ROUTER";
    hre.tracer.nameTags[WETH] = "WETH";
    hre.tracer.nameTags[USDC] = "USDC";
    hre.tracer.nameTags[NFTPOOL] = "NFTPOOL";
  });

  describe("Cruize Camelot Vault Initialization", () => {
    it.only("Initialize Cruize Camelot Vault", async () => {
      await crCamelotVault.initialize("cr-spNFT", "cr-spNFT", "");
    });
  });

  describe("Camelot Vault", () => {
    it.only("Add liquidity in weth/usdc pool", async () => {
      await usdc.connect(externalUser).approve(ROUTER, constants.MaxUint256);
      await weth.connect(externalUser).approve(ROUTER, constants.MaxUint256);
      await router
        .connect(externalUser)
        .addLiquidity(
          WETH,
          USDC,
          parseEther("4"),
          BigNumber.from("12000000000"),
          parseEther("0"),
          parseEther("0"),
          EXTERNAL_ACCOUNT,
          "1701913280"
        );
    });
    it.only("Create Position in Camelot Vault", async () => {
      const lp_balance:BigNumber = await lp.callStatic.balanceOf(EXTERNAL_ACCOUNT);
      await lp.connect(externalUser).approve(NFTPOOL, constants.MaxUint256);
      await nftPool.connect(externalUser).createPosition(lp_balance.div(2), 0);
    });
  });

  describe("Cruize Camelot Vault", () => {
    it.only("1st Deposit::Deposit spNFT in crCamelotVault", async () => {
      const tokenId = await nftPool.callStatic.tokenOfOwnerByIndex(
        EXTERNAL_ACCOUNT,
        0
      );
      await nftPool
        .connect(externalUser)
        .approve(crCamelotVault.address, tokenId);
      await crCamelotVault.connect(externalUser).deposit(tokenId);
    });

    it.only("2nd Deposit::Deposit spNFT in crCamelotVault", async () => {
      const lp_balance:BigNumber = await lp.callStatic.balanceOf(EXTERNAL_ACCOUNT);
      await nftPool.connect(externalUser).createPosition(lp_balance, 0);
      const tokenId = await nftPool.callStatic.tokenOfOwnerByIndex(
        EXTERNAL_ACCOUNT,
        0
      );
      await nftPool
        .connect(externalUser)
        .approve(crCamelotVault.address, tokenId);
      await crCamelotVault.connect(externalUser).deposit(tokenId);
    });
  });
});

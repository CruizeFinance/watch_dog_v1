import hre, { ethers } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { impersonateAccount } from "@nomicfoundation/hardhat-network-helpers";
import { parseEther, parseUnits } from "ethers/lib/utils";
import { increaseTo } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";

describe("testing RDNT vaults", function () {
  let owner: SignerWithAddress;
  let depositor: SignerWithAddress;
  let deployer: SignerWithAddress;
  let cruizeProxy: Contract;
  let proxy: Contract;
  let usdc:Contract;
  let USDC = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  let DEPOSITOR = "0x5bdf85216ec1e38D6458C870992A69e38e03F7Ef"
  let DEPOLYER = "0x96d331Ca0D9c9D1b53A46CD050A698ae4c4c246F"
  let OWNER = "0x33aD52AD73e59995653E1e9C328C9899a8E6A6Dd";
  let ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

  before(async () => {
    // console.log("Before",await ethers.getSigners());
    await impersonateAccount(DEPOSITOR);
    await impersonateAccount(DEPOLYER);
    await impersonateAccount(OWNER);
    owner = await ethers.getImpersonatedSigner(OWNER);
    deployer = await ethers.getImpersonatedSigner(DEPOLYER);
    depositor = await ethers.getImpersonatedSigner(DEPOSITOR)
    proxy = await ethers.getContractAt("CruizeProxy","0xaA553dEdd3Cd9f6E2cd36A1E9B102Eb4e70322c0",deployer)
    cruizeProxy = await ethers.getContractAt("Cruize","0xaA553dEdd3Cd9f6E2cd36A1E9B102Eb4e70322c0",deployer)
    usdc = await ethers.getContractAt("IUSDC",USDC,depositor)

    hre.tracer.nameTags[deployer.address] = "DEPLOYER";
    hre.tracer.nameTags[depositor.address] = "DEPOSITOR";
    hre.tracer.nameTags[USDC] = "USDC";

  });

  it.only("deploy new implementation", async () => {
    const CRUIZE_LOGIC = await ethers.getContractFactory("Cruize",deployer);
    let newLogic = await CRUIZE_LOGIC.deploy();
    await proxy.upgradeTo(newLogic.address)
  });

  it.only("1: approve usdc", async () => {
    await usdc.approve(cruizeProxy.address,ethers.constants.MaxUint256)
  });

  it.only("2: set lending pool", async () => {
    await cruizeProxy.connect(owner).setLendingPoolParams("0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1","0xBb5cA40b2F7aF3B1ff5dbce0E9cC78F8BFa817CE")
  });
  
  it.only("3: deposit usdc", async () => {
    await cruizeProxy.connect(depositor).deposit(USDC, parseUnits("2000",6));
    console.log(await cruizeProxy.connect(depositor).callStatic.collateral())
    await increaseTo(1684924017);
    console.log(await cruizeProxy.connect(depositor).callStatic.collateral())
    console.log(await cruizeProxy.connect(depositor).callStatic.calculateAPY(USDC,parseUnits("2000",6)))

  });

  it("4: Withdraw new balance", async () => {
    await cruizeProxy.connect(depositor).instantWithdrawal(USDC,parseUnits("210",6))
  });

});
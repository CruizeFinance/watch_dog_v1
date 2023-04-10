import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { BigNumber, Contract ,constants} from "ethers";
import { parseEther, parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { mine,setStorageAt,time } from "@nomicfoundation/hardhat-network-helpers";

export const Impersonate = async(address:string):Promise<SignerWithAddress> =>{
    await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
      });
      const account = await ethers.getSigner(address)
      return account;
}

describe("work flow from curize vault to cruize contract", function () {
  let signer: SignerWithAddress;
  let deployer: SignerWithAddress;
  let anonymous: SignerWithAddress;
  let proxy:Contract;
  let minter:Contract;
  let ramsesVault:Contract;
  let ramsesVaultProxy:Contract;
  let weth:Contract
  let usdc:Contract
  const WETH = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  const USDC  = "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8";
  const RAM  = "0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418";
  const LP  = "0x5513a48F3692Df1d9C793eeaB1349146B2140386";
  const MINTER  = "0xAAAA0b6BaefaeC478eB2d1337435623500AD4594";

  before(async () => {
      [signer, deployer,anonymous] = await ethers.getSigners();

    weth = await ethers .getContractAt("IWETH",WETH,signer);
    usdc = await ethers .getContractAt("IUSDC",USDC,signer);
    
    
    const RAMSES_VAULT = await ethers.getContractFactory("RamsesVault",signer);
    ramsesVault = await RAMSES_VAULT.deploy();
    
    const RAMSES_PROXY = await ethers.getContractFactory("RamsesVaultProxy",deployer);
    proxy = await RAMSES_PROXY.deploy(ramsesVault.address,deployer.address,"0x")
    
    ramsesVaultProxy = await ethers.getContractAt("RamsesVault",proxy.address,signer)

    minter = await ethers.getContractAt("IMinter",MINTER,signer)
    
    hre.tracer.nameTags[ramsesVaultProxy.address] = "RAMSES-PROXY";
    hre.tracer.nameTags[ramsesVault.address] = "RAMSES-LOGIC";
    
    hre.tracer.nameTags[anonymous.address] = "anonymous";
    hre.tracer.nameTags[deployer.address] = "deployer";
    hre.tracer.nameTags[signer.address] = "signer";
    
    hre.tracer.nameTags[weth.address] = "WETH";
    hre.tracer.nameTags[weth.address] = "WETH";
    hre.tracer.nameTags[usdc.address] = "USDC";
    hre.tracer.nameTags[RAM] = "RAM";
    hre.tracer.nameTags[LP] = "LP";

    hre.tracer.nameTags["0xaaa87963efeb6f7e0a2711f397663105acb1805e"] = "ROUTER";
    hre.tracer.nameTags["0xAAA2564DEb34763E3d05162ed3f5C2658691f499"] = "VOTER";
    hre.tracer.nameTags["0xDBA865F11bb0a9Cd803574eDd782d8B26Ee65767"] = "GUAGE";
    hre.tracer.nameTags["0x5513a48F3692Df1d9C793eeaB1349146B2140386"] = "VOTING-POOL";
    hre.tracer.nameTags["0xAAA343032aA79eE9a6897Dab03bef967c3289a06"] = "voting-escrow";

    async function setTokenBalance(account:string,token:string,balance:BigNumber,slot:number):Promise<void> {
        
        const toBytes32 = (bn:BigNumber) => {
            return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
          };
        
          const setStorage = async (address:string, index:string, value:string) => {
            await setStorageAt(address,index,value)
            await mine();
    
            await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
            await ethers.provider.send("evm_mine", []); // Just mines to the next block
          };

        // Get storage slot index
        const index = ethers.utils.solidityKeccak256(
            ["uint256", "uint256"],
            [account, slot] // key, slot
          );
        
    // Manipulate local balance (needs to be bytes32 string)
    await setStorage(
        token,
        index.toString(),
        toBytes32(balance).toString()
      );
    }
    const SLOT = 51
    await setTokenBalance(signer.address,USDC,parseUnits("100000"),SLOT);
    await setTokenBalance(anonymous.address,USDC,parseUnits("100000"),SLOT);
    await weth.deposit({value:parseEther("10")})
    await weth.connect(anonymous).deposit({value:parseEther("10")})

    await usdc.approve(ramsesVaultProxy.address,constants.MaxUint256)
    await weth.approve(ramsesVaultProxy.address,constants.MaxUint256)

    await usdc.connect(anonymous).approve(ramsesVaultProxy.address,constants.MaxUint256)
    await weth.connect(anonymous).approve(ramsesVaultProxy.address,constants.MaxUint256)

});

describe("Ramses Vault", () => {
    it.only("initialize ramses vault", async () => {
     await ramsesVaultProxy.initialize(
        weth.address,
        usdc.address,
        false,
        signer.address
     )
     await minter.update_period();
    });
    it.only("add liquidity", async () => {
      await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6));
    });

    it.only("[signer][after 1 hour]:add liquidity & claim RAM tokens & lock RAM tokens", async () => {
        const oneHourInSeconds = time.duration.hours(1);
        await time.increase(oneHourInSeconds);
        await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6))

        // // await ramsesVaultProxy.closeRound();
        // await ramsesVaultProxy.withdraw()

    });

    it.only("[signer][after 2 hour]:add liquidity & claim RAM tokens & lock RAM tokens", async () => {
        const oneHourInSeconds = time.duration.hours(1);
        await time.increase(oneHourInSeconds);
        await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6))
    });

    it.only("[anonymous][after 2 hour]:add liquidity & claim RAM tokens & lock RAM tokens", async () => {
        await ramsesVaultProxy.connect(anonymous).deposit(parseEther("1"),parseUnits("2000",6))
    });

    it.only("[signer][after 2 hour]:withdraw liquidity", async () => {
      await ramsesVaultProxy.withdraw()
    });

    it.only("[anonymous][after 2 hour]:withdraw liquidity", async () => {
      await ramsesVaultProxy.connect(anonymous).withdraw();
      await ramsesVaultProxy.closeRound();

    });

    it.only("[after 6 days]:Throw if add liquidity after round expiration", async () => {
        const sixDaysInSeconds = time.duration.days(9);
        await time.increase(sixDaysInSeconds);
        await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6))
    });
  });

  describe("Ramses Vault With Locking", () => {
    it("initialize ramses vault", async () => {
     await ramsesVaultProxy.initialize(
        weth.address,
        usdc.address,
        false,
        signer.address
     );
    });
    
    it("add liquidity", async () => {
      await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6));
    });

    it("[signer][after 1 hour]:add liquidity & claim RAM tokens & lock RAM tokens", async () => {
        const oneHourInSeconds = time.duration.hours(5);
        await time.increase(oneHourInSeconds);
        await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6))
    });

    it("[signer][after 2 hour]:add liquidity & claim RAM tokens & lock RAM tokens", async () => {
        const oneHourInSeconds = time.duration.hours(5);
        await time.increase(oneHourInSeconds);
        await ramsesVaultProxy.deposit(parseEther("2"),parseUnits("4000",6))
    });

    it("[anonymous][after 2 hour]:add liquidity & claim RAM tokens & lock RAM tokens", async () => {
        await ramsesVaultProxy.connect(anonymous).deposit(parseEther("1"),parseUnits("2000",6))
    });

    it("[signer][after 2 hour]:withdraw liquidity", async () => {
      await ramsesVaultProxy.withdraw()
      await ramsesVaultProxy.connect(anonymous).withdraw()
    });

    it("[signer][after 2 hour]:withdraw liquidity", async () => {
      await ramsesVaultProxy.claimFees()
    });

    it("[anonymous][after 2 hour]:withdraw liquidity", async () => {
      await ramsesVaultProxy.connect(anonymous).withdraw();
      await ramsesVaultProxy.closeRound();

    });

    it("[after 6 days]:Throw if add liquidity after round expiration", async () => {
        const sixDaysInSeconds = time.duration.days(5);
        await time.increase(sixDaysInSeconds);
        await ramsesVaultProxy.claimFees()

        // await expect(ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6))).to.be.revertedWithCustomError(ramsesVaultProxy,"ROUND_EXPIRED")
    });

    it("Close round & claim Fee", async () => {
    await minter.update_period();
    // await ramsesVaultProxy.deposit(parseEther("1"),parseUnits("2000",6));
    // await ramsesVaultProxy.withdraw()
    await ramsesVaultProxy.closeRound();
    });
  });

});


/// number of use cases
/// 1- add liquidity [for the first time we will just deposit]
/// 2- add liquidity after sometime [second time we can claim RAM tokens and lock RAM tokens in order to get veNFT]
///     1- add liquidity
///     1- deposit lp in gauge
///     2- claim RAM tokens
///     3- createLock (lock the RAM tokens)
///     4- Get veNFT
/// 3- add liquidity after sometime
///     1- add liquidity
///     1- deposit lp in gauge
///     2- claim RAM tokens
///     3- increase lock amount and does not update the lock period
/// 3- add liquidity after 6 days
///     1- add liquidity
///     2- claim RAM tokens
///     3- deposit lp in gauge
///     4- claim RAM tokens
///     4- withdraw all lp tokens
///     4- reset vote
///     4- withdraw RAM tokens

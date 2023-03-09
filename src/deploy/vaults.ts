import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { DeployFunction, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { contractNames } from "../ts/deploy";
import { parseEther } from "ethers/lib/utils";
import { BigNumber, Contract } from "ethers";

interface IMapping {
  [key: string]: string;
}

const deployContract: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  const { deployments } = hre;
  const { deploy, get } = deployments;
  const { CruizeVault, CrMaster } = contractNames;

  let crToken: Deployment;
  let cruize: Deployment;

  const signer: SignerWithAddress = (await hre.ethers.getSigners())[0];
  const deployer = signer.address;
  const chainId = await hre.getChainId();
  let ETHADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  let safes: IMapping = {
    "5": "0xd5dC7C061D2a69a875754E6a50C4454B8e14DAC7", // goerli
    "421613": "0xfb7c160144b4fA6DaaeD472D59EEABBEa4b07648", //arbitrum_goerli
    "8081": "", // shardeum
    "43113": "0x4e0427e2cb2bC1288ed649346901dF0489057E26", // avalache_fuji
  };

  // deploy master copy of crTokens
  await deploy(CrMaster, {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
  crToken = await get(CrMaster);

  // deploy Cruiz Vault
  await deploy(CruizeVault, {
    from: deployer,
    args: [
      deployer,
      safes[chainId],
      crToken.address,
      parseEther("10"),
      parseEther("10"),
    ],
    log: true,
    deterministicDeployment: false,
  });
  cruize = await get(CruizeVault);

  let CruizeInstance: Contract = await ethers.getContractAt(
    CruizeVault,
    cruize.address,
    signer
  );

  const weth = await deploy("wethMintable", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });

  let crWETH = await CruizeInstance.callStatic.cruizeTokens(weth.address);

  const usdc = await deploy("usdcMintable", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });

  let crUSDC = await CruizeInstance.callStatic.cruizeTokens(usdc.address);

  const wbtc = await deploy("wbtcMintable", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });

  let crWBTC = await CruizeInstance.callStatic.cruizeTokens(wbtc.address);

  const dai = await deploy("daiMintable", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });
  let crDAI = await CruizeInstance.callStatic.cruizeTokens(dai.address);
  
  if(crWETH == ethers.constants.AddressZero)
  await CruizeInstance.createToken(
    "Cruize WETH",
    "crWETH",
    weth.address,
    18,
    parseEther("10000")
  );

  if(crUSDC == ethers.constants.AddressZero)
  await CruizeInstance.createToken(
    "Cruize USDC",
    "crUSDC",
    usdc.address,
    6,
    parseEther("10000")
  );

  if(crWBTC == ethers.constants.AddressZero)
  await CruizeInstance.createToken(
    "Cruize WBTC",
    "crWBTC",
    wbtc.address,
    18,
    parseEther("10000")
    );
    
  if(crDAI == ethers.constants.AddressZero)
  await CruizeInstance.createToken(
    "Cruize DAI",
    "crDAI",
    dai.address,
    18,
    parseEther("10000")
  );

  

  console.table({
    chainId:chainId,
    crToken:crToken.address,
    cruizeModule:cruize.address,
    safe:safes[chainId],
    weth:weth.address,
    wbtc:wbtc.address,
    usdc:usdc.address,
    dai:dai.address,
    crWBTC,
    crWETH,
    crUSDC,
    crDAI
  })

  // await CruizeInstance.initRounds(weth[chainId], BigNumber.from("1"));
  // await CruizeInstance.initRounds(wbtc.address, BigNumber.from("1"));
  // await CruizeInstance.initRounds(usdc.address, BigNumber.from("1"));
  // await CruizeInstance.initRounds(dai.address, BigNumber.from("1"));
  // console.log(await CruizeInstance.callStatic.cruizeTokens(ETHADDRESS))
  // console.log(await CruizeInstance.callStatic.cruizeTokens(DAIADDRESS))

  // await CruizeInstance.deposit(ETHADDRESS, parseEther("1"), {
  //   value: parseEther("1"),
  // });

  // await CruizeInstance
  // .withdrawInstantly(parseEther("1"), ETHADDRESS)



  try {
    await hre.run("verify", {
      address: cruize.address,
      constructorArgsParams: [
        deployer,
        safes[chainId],
        crToken.address,
        parseEther("10").toString(),
        parseEther("10").toString(),
      ],
    });
  } catch (error) {
    console.log(error)
    console.log(
      `Smart contract at address ${cruize.address} is already verified`
    );
  }

  try {
    await hre.run("verify", {
      address: usdc.address,
      constructorArgsParams: [
        "DAI","DAI"
      ],
    });
  } catch (error) {
    console.log(
      `Smart contract at address ${usdc.address} is already verified`
    );
  }

};

export default deployContract;

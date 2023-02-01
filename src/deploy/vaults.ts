import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { DeployFunction, Deployment } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { contractNames } from '../ts/deploy';
import { parseEther } from 'ethers/lib/utils';
import { BigNumber, Contract } from 'ethers';

interface ITokens {
  [key:string]: string;
}

const deployContract: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { deployments } = hre;
  const { deploy, get } = deployments;
  const {
    CruizeVault,
    CrMaster
    } = contractNames;

  let crToken: Deployment;
  let cruize: Deployment;

  const signer:SignerWithAddress = (await hre.ethers.getSigners())[0];
  const deployer = signer.address
  const chainId = await hre.getChainId();
  let tokens:ITokens = {
    "5":"0xB8096bC53c3cE4c11Ebb0069Da0341d75264B104",
    "421613":"0xB8096bC53c3cE4c11Ebb0069Da0341d75264B104", //arbitrum
    "8081":"0xB8096bC53c3cE4c11Ebb0069Da0341d75264B104" // shardeum
  }
  let ETHADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  let DAIADDRESS = "0xB8096bC53c3cE4c11Ebb0069Da0341d75264B104";

  console.log(tokens[chainId])


  await deploy(CrMaster, {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  }
  )
  crToken = await get(CrMaster);



  await deploy(CruizeVault, {
    from: deployer,
    args: [
      "0x9A3310233aaFe8930d63145CC821FF286c7829e1",
      "0xBe4C54c29f95786ca5e94ba9701FD5758183BFd4",
      crToken.address,
      parseEther("10")
    ],
    log: true,
    deterministicDeployment: false,
  }
  )
  cruize = await get(CruizeVault);

  let CruizeInstance:Contract = await ethers.getContractAt(CruizeVault,cruize.address,signer)
  await CruizeInstance.createToken(
    "Cruize ETH",
    "crETH",
    ETHADDRESS,
    18,
    parseEther("1000")
  )

  await CruizeInstance.createToken(
    "Cruize DAI",
    "crDAI",
    DAIADDRESS,
    18,
    parseEther("1000")
  )

  await CruizeInstance.initRounds(ETHADDRESS, BigNumber.from("1"));
  await CruizeInstance.initRounds(DAIADDRESS, BigNumber.from("1"));

      console.log(await CruizeInstance.callStatic.cruizeTokens(ETHADDRESS))
      console.log(await CruizeInstance.callStatic.cruizeTokens(DAIADDRESS))

  // await CruizeInstance.deposit(ETHADDRESS, parseEther("1"), {
  //   value: parseEther("1"),
  // });

  // await CruizeInstance
  // .withdrawInstantly(parseEther("1"), ETHADDRESS)

  try {
    await hre.run('verify', {
      address: cruize.address,
      constructorArgsParams: [
        "0x9A3310233aaFe8930d63145CC821FF286c7829e1",
        "0xBe4C54c29f95786ca5e94ba9701FD5758183BFd4",
        crToken.address,
        parseEther("10").toString()
      ],
    })
  } catch (error) {
    console.log(`Smart contract at address ${cruize.address} is already verified`)
  }


}

export default deployContract

import { BigNumber, Contract, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";

const deployContracts = async (contractName: string, signer: Signer) => {
  const contract = await ethers.getContractFactory(contractName, signer);
  const deployedContract = await contract.deploy();
  return deployedContract;
};



const depositERC20 = async (
  cruizeModule: Contract,
  tokenContract: Contract,
  amount: any
) => {
  await tokenContract.approve(cruizeModule.address, parseEther("1000"));
  await cruizeModule.deposit(tokenContract.address, parseEther(amount));
};

const createCruizeToken = async (
  name: string,
  symbol: string,
  address: Address,
  decimals: number,
  cap: string,
  cruizeContract: Contract
) => {
  const tx = await cruizeContract.createToken(
    name,
    symbol,
    address,
    decimals,
    parseEther(cap)
  );
  return tx;
};
const toBigNumber = (Number:number) =>{
  return BigNumber.from(Number).toString()
}
const str = (BN:BigNumber)=>{
  return BN.toString()
}
const errorContext = (expectedBN:BigNumber,actualBN:BigNumber) => {
  return`excepted ${expectedBN} actule ${actualBN}`
}

export {toBigNumber, errorContext,deployContracts, createCruizeToken, depositERC20,str };

import { Contract, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";

const deployContracts = async (contractName: string, signer: Signer) => {
  const contract = await ethers.getContractFactory(contractName, signer);
  const deployedContract = await contract.deploy();
  return deployedContract;
};

const createCruizeToken = async (
  contract: Contract,
  name: string,
  symbol: string,
  decimal: any,
  tokenaddress: any
) => {
  const res = await contract.createToken(name, symbol, tokenaddress, decimal);
  let tx = await res.wait();
  tx = await contract.cruizeTokens(tokenaddress);
  return tx;
};

const DepositERC20 = async (
  cruizeModule: Contract,
  tokenContract: Contract,
  amount: any
) => {
  await tokenContract.approve(cruizeModule.address, parseEther(amount));
  await cruizeModule.deposit(tokenContract.address, parseEther(amount));
};

export { deployContracts, createCruizeToken, DepositERC20 };

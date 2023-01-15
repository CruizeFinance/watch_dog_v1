
import { AnyRecord } from "dns";
import { Contract } from "ethers";
import { parseEther } from "ethers/lib/utils";
import hre, { ethers } from "hardhat";


    const depoloyContracts =async (contractName:any,signer:any)=>{
        const contract =  await ethers.getContractFactory(contractName, signer);
       const  deployedContract =  await contract.deploy();
        return deployedContract;
     }
     
   const createCruizeToken = async(contract:Contract,name:string,symbol:string,decimal:any,tokenaddress:any)=>{
   const res =  await contract.createToken(
        name,
        symbol,
        tokenaddress,
        decimal
      );
      let tx = await res.wait();
      tx = await contract.cruizeTokens(tokenaddress);
      return tx

   }

   const DepositERC20 = async(cruizeModule:Contract,tokenContract:Contract,amount:any)=>{
      await tokenContract.approve(cruizeModule.address, parseEther(amount));
      await cruizeModule.deposit(tokenContract.address, parseEther(amount));
   }

export {depoloyContracts,createCruizeToken,DepositERC20}
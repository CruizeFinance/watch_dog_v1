import { BigNumber, Contract } from "ethers";

const depositERC20 = async (
    cruizeModule: Contract,
    tokenContract: Contract,
    amount:BigNumber
  ) => {
    await tokenContract.approve(cruizeModule.address, amount);
    await cruizeModule.deposit(tokenContract.address,amount);
  };
  export {depositERC20}
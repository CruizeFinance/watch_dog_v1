import { parseEther } from "ethers/lib/utils";
import { IChainTokens, ITokens } from "./interfaces";

const arbitrum: ITokens = {
  WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
  WBTC: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
  USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
};
const goerli: ITokens = {
  WETH: "0x2f87d4CF0D02248EB38CD06A3F3266C7Bc6e5bd2",
  WBTC: "0x02245d57122896af490174f7421bD5a73CF7b0dc",
  USDC: "0xf029E7204D23A97CCd788e808c0f45ddB6745b25",
};
const arbitrum_goerli: ITokens = {
  WETH: "0x0BA9C96583F0F1b192872A05e3c4Bc759afD36B2",
  WBTC: "0xff737BA76F49bf82D7f13378d787685B0c6669Db",
  USDC: "0x7Ef1F6bBEe3CA066b31642fFc53D42C5435C6937",
};
const avalanche_fuji: ITokens = {
  WETH: "0x823c0e06e78aFC4481a4154aCBBfe445a3C50E65",
  WBTC: "0x3c44b3F782900c6124e0211EE0Ab54c76cdE490b",
  USDC: "0x703Cc67AA5F0bcf34cd9bA5200C051daf7BA3476",
};
const shardeum_sphinx: ITokens = {
  WETH: "0xD6f9819252d6Dd411523A3599834e97df34aC5A9",
  WBTC: "0x4783c71581Cc7f7Dde4c627fAfF57832Dc6B57f0",
  USDC: "0x44975e82B7D2570516bc57e8F49b3aB92767f2f1",
};
const polygon_mumbai: ITokens = {
  WETH: "0xafAa83252d90B6a209000eC389E943b03FdCB0F8",
  WBTC: "0xedC7632768B7239BBA9F66cB807e14Cb7aF7a04E",
  USDC: "0xE7AFdD06DfD32a3175687D77Fd9a4eD270d7E814",
};

const chainTokenAddresses: IChainTokens = {
  "42161": arbitrum,
  "5": goerli,
  "421613": arbitrum_goerli,
  "43113": avalanche_fuji,
  "8082": shardeum_sphinx,
  "80001": polygon_mumbai,
};
const crTokensDetiles = [
  {
    tokenName: "WETH",
    crTokenName: "Cruize WETH",
    crSymbol: "crWETH",
    decimal: 18,
    cap: parseEther("10000").toString(),
  },
  {
    tokenName: "USDC",
    crTokenName: "Cruize USDC",
    crSymbol: "crUSDC",
    decimal: 6,
    cap: "10000000000",
  },
  {
    tokenName: "WBTC",
    crTokenName: "Cruize WBTC",
    crSymbol: "crWTBC",
    decimal: 8,
    cap: "100000000000",
  },
];

export { chainTokenAddresses, crTokensDetiles };

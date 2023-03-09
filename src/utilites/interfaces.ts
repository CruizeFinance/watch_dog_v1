interface ITokens {
    [key: string]: string;
  }
  interface IChainTokens {
    [key: string]: ITokens;
  }
  export { IChainTokens, ITokens };
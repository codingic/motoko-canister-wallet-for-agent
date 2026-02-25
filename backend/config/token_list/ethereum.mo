import Types "../../types";

module {
  public let TOKENS : [Types.ConfiguredTokenConfig] = [
    {
      network = "ethereum";
      symbol = "USDC";
      name = "USD Coin";
      token_address = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
      decimals = 6;
    },
    {
      network = "ethereum";
      symbol = "USDT";
      name = "Tether USD";
      token_address = "0xdac17f958d2ee523a2206206994597c13d831ec7";
      decimals = 6;
    },
    {
      network = "ethereum";
      symbol = "UNI";
      name = "Uniswap";
      token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984";
      decimals = 18;
    },
  ];
}

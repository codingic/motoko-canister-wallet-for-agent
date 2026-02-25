import Types "../../types";

module {
  public let TOKENS : [Types.ConfiguredTokenConfig] = [
    {
      network = "avalanche";
      symbol = "USDC";
      name = "USD Coin";
      token_address = "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e";
      decimals = 6;
    },
    {
      network = "avalanche";
      symbol = "USDT";
      name = "Tether USD";
      token_address = "0x9702230a8ea53601f5cd2dc00fdbc13d4df4a8c7";
      decimals = 6;
    },
  ];
}

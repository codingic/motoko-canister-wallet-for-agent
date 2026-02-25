import Types "../../types";

module {
  public let TOKENS : [Types.ConfiguredTokenConfig] = [
    {
      network = "arbitrum";
      symbol = "USDC";
      name = "USD Coin";
      token_address = "0xaf88d065e77c8cc2239327c5edb3a432268e5831";
      decimals = 6;
    },
    {
      network = "arbitrum";
      symbol = "USDT";
      name = "Tether USD";
      token_address = "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9";
      decimals = 6;
    },
  ];
}

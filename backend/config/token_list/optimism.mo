import Types "../../types";

module {
  public let TOKENS : [Types.ConfiguredTokenConfig] = [
    {
      network = "optimism";
      symbol = "USDC";
      name = "USD Coin";
      token_address = "0x0b2c639c533813f4aa9d7837caf62653d097ff85";
      decimals = 6;
    },
    {
      network = "optimism";
      symbol = "USDT";
      name = "Tether USD";
      token_address = "0x94b008aa00579c1307b0ef2c499ad98a8ce58e58";
      decimals = 6;
    },
  ];
}

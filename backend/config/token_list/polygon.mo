import Types "../../types";

module {
  public let TOKENS : [Types.ConfiguredTokenConfig] = [
    {
      network = "polygon";
      symbol = "USDC";
      name = "USD Coin";
      token_address = "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359";
      decimals = 6;
    },
    {
      network = "polygon";
      symbol = "USDT";
      name = "Tether USD";
      token_address = "0xc2132d05d31c914a87c6611c10748aeb04b58e8f";
      decimals = 6;
    },
  ];
}

import Types "./types";

module {
  // Mirrors backend/chains.rs module registry. Individual chain modules are ported separately.
  public let registered_chain_modules : [Text] = [
    Types.APTOS_MAINNET,
    Types.BITCOIN,
    Types.ETHEREUM,
    Types.INTERNET_COMPUTER,
    Types.NEAR_MAINNET,
    Types.SEPOLIA,
    Types.SOLANA,
    Types.SOLANA_TESTNET,
    Types.SUI_MAINNET,
    Types.TON_MAINNET,
    Types.TRON,
  ];
}

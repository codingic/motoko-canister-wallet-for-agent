import Char "mo:base/Char";
import Text "mo:base/Text";
import CfgTokenList "./config/token_list_config";
import Aptos "./aptos_mainnet";
import EvmRpc "./evm_rpc";
import Error "./error";
import Icp "./internet_computer";
import Near "./near_mainnet";
import Sol "./solana";
import Sui "./sui_mainnet";
import Ton "./ton_mainnet";
import Trx "./tron";
import Types "./types";

module {
  public func normalize_network_name(input : Text) : Text {
    let trimmed = Text.trim(input, #predicate(func(c) = Char.isWhitespace(c)));
    let lower = Text.toLowercase(trimmed);
    Text.replace(lower, #char '-', "_")
  };

  // Fast path for configured tokens. Per-chain dynamic discovery can be added incrementally.
  public func discover_token_metadata(
    network : Text,
    token_address : Text,
  ) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let normalized = normalize_network_name(network);
    let tokenAddress = Text.trim(token_address, #char ' ');
    if (Text.size(tokenAddress) == 0) {
      return #Err(#InvalidInput("token_address is required"));
    };

    for (t in CfgTokenList.configured_tokens(normalized).vals()) {
      if (t.token_address == tokenAddress) {
        return #Ok({
          network = normalized;
          symbol = t.symbol;
          name = t.name;
          token_address = t.token_address;
          decimals = t.decimals;
        });
      };
    };

    if (
      normalized == Types.ETHEREUM or
      normalized == Types.SEPOLIA or
      normalized == Types.BASE or
      normalized == Types.BSC or
      normalized == Types.ARBITRUM or
      normalized == Types.OPTIMISM or
      normalized == Types.AVALANCHE or
      normalized == Types.OKX or
      normalized == Types.POLYGON
    ) {
      return await EvmRpc.discover_erc20_token(normalized, tokenAddress);
    };

    if (normalized == Types.SUI_MAINNET) {
      return await Sui.discover_coin_type_token(tokenAddress);
    };

    if (normalized == Types.APTOS_MAINNET) {
      return await Aptos.discover_coin_type_token(tokenAddress);
    };

    if (normalized == Types.NEAR_MAINNET) {
      return await Near.discover_nep141_token(tokenAddress);
    };

    if (normalized == Types.TON_MAINNET) {
      return await Ton.discover_jetton_token(tokenAddress);
    };

    if (normalized == Types.INTERNET_COMPUTER) {
      return await Icp.discover_icrc_token(tokenAddress);
    };

    if (normalized == Types.SOLANA or normalized == Types.SOLANA_TESTNET) {
      return await Sol.discover_spl_token(normalized, tokenAddress);
    };

    if (normalized == Types.TRON) {
      return await Trx.discover_trc20_token(tokenAddress);
    };

    #Err(#Unimplemented({
      network = normalized;
      operation = "token metadata discovery";
    }))
  };
}

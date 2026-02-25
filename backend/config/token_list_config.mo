import Char "mo:base/Char";
import Text "mo:base/Text";
import Types "../types";
import arbitrum "./token_list/arbitrum";
import avalanche "./token_list/avalanche";
import base "./token_list/base";
import bsc "./token_list/bsc";
import ethereum "./token_list/ethereum";
import icp "./token_list/internet_computer";
import optimism "./token_list/optimism";
import polygon "./token_list/polygon";
import sepolia "./token_list/sepolia";
import solana "./token_list/solana";

module {
  public type ConfiguredToken = Types.ConfiguredTokenConfig;

  public func configured_tokens(network : Text) : [ConfiguredToken] {
    switch (normalize_config_network_name(network)) {
      case ("internet_computer") icp.TOKENS;
      case ("ethereum") ethereum.TOKENS;
      case ("sepolia") sepolia.TOKENS;
      case ("base") base.TOKENS;
      case ("polygon") polygon.TOKENS;
      case ("arbitrum") arbitrum.TOKENS;
      case ("optimism") optimism.TOKENS;
      case ("bsc") bsc.TOKENS;
      case ("avalanche") avalanche.TOKENS;
      case ("solana") solana.TOKENS;
      case (_) [];
    };
  };

  func normalize_config_network_name(network : Text) : Text {
    let trimmed = Text.trim(network, #predicate(func(c) = Char.isWhitespace(c)));
    let lower = Text.toLowercase(trimmed);
    Text.replace(lower, #char '-', "_");
  };
}

import Char "mo:base/Char";
import Text "mo:base/Text";
import Types "../types";

module {
  public type ExplorerConfig = {
    network : Text;
    address_url_template : Text;
    token_url_template : ?Text;
  };

  public func configured_explorer(network : Text) : ?ExplorerConfig {
    let normalized = normalize_config_network_name(network);
    switch (normalized) {
      case ("ethereum") {
        ?{
          network = Types.ETHEREUM;
          address_url_template = "https://etherscan.io/address/{address}";
          token_url_template = ?"https://etherscan.io/token/{token}?a={address}";
        };
      };
      case ("sepolia") {
        ?{
          network = Types.SEPOLIA;
          address_url_template = "https://sepolia.etherscan.io/address/{address}";
          token_url_template = ?"https://sepolia.etherscan.io/token/{token}?a={address}";
        };
      };
      case ("base") {
        ?{
          network = Types.BASE;
          address_url_template = "https://basescan.org/address/{address}";
          token_url_template = ?"https://basescan.org/token/{token}?a={address}";
        };
      };
      case ("bsc") {
        ?{
          network = Types.BSC;
          address_url_template = "https://bscscan.com/address/{address}";
          token_url_template = ?"https://bscscan.com/token/{token}?a={address}";
        };
      };
      case ("arbitrum") {
        ?{
          network = Types.ARBITRUM;
          address_url_template = "https://arbiscan.io/address/{address}";
          token_url_template = ?"https://arbiscan.io/token/{token}?a={address}";
        };
      };
      case ("optimism") {
        ?{
          network = Types.OPTIMISM;
          address_url_template = "https://optimistic.etherscan.io/address/{address}";
          token_url_template = ?"https://optimistic.etherscan.io/token/{token}?a={address}";
        };
      };
      case ("avalanche") {
        ?{
          network = Types.AVALANCHE;
          address_url_template = "https://snowtrace.io/address/{address}";
          token_url_template = ?"https://snowtrace.io/token/{token}?a={address}";
        };
      };
      case ("polygon") {
        ?{
          network = Types.POLYGON;
          address_url_template = "https://polygonscan.com/address/{address}";
          token_url_template = ?"https://polygonscan.com/token/{token}?a={address}";
        };
      };
      case ("okx") {
        ?{
          network = Types.OKX;
          address_url_template = "https://www.oklink.com/zh-hans/x-layer/address/{address}";
          token_url_template = ?"https://www.oklink.com/zh-hans/x-layer/token/{token}?tab=holders";
        };
      };
      case ("bitcoin") {
        ?{
          network = Types.BITCOIN;
          address_url_template = "https://mempool.space/address/{address}";
          token_url_template = null;
        };
      };
      case ("internet_computer") {
        ?{
          network = Types.INTERNET_COMPUTER;
          address_url_template = "https://dashboard.internetcomputer.org/canister/{address}";
          token_url_template = ?"https://dashboard.internetcomputer.org/canister/{token}";
        };
      };
      case ("solana") {
        ?{
          network = Types.SOLANA;
          address_url_template = "https://solscan.io/account/{address}";
          token_url_template = ?"https://solscan.io/token/{token}";
        };
      };
      case ("solana_testnet") {
        ?{
          network = Types.SOLANA_TESTNET;
          address_url_template = "https://solscan.io/account/{address}?cluster=testnet";
          token_url_template = ?"https://solscan.io/token/{token}?cluster=testnet";
        };
      };
      case ("tron") {
        ?{
          network = Types.TRON;
          address_url_template = "https://tronscan.org/#/address/{address}";
          token_url_template = ?"https://tronscan.org/#/token20/{token}";
        };
      };
      case ("ton_mainnet") {
        ?{
          network = Types.TON_MAINNET;
          address_url_template = "https://tonviewer.com/{address}";
          token_url_template = ?"https://tonviewer.com/{token}";
        };
      };
      case ("near_mainnet") {
        ?{
          network = Types.NEAR_MAINNET;
          address_url_template = "https://nearblocks.io/address/{address}";
          token_url_template = ?"https://nearblocks.io/token/{token}";
        };
      };
      case ("aptos_mainnet") {
        ?{
          network = Types.APTOS_MAINNET;
          address_url_template = "https://explorer.aptoslabs.com/account/{address}?network=mainnet";
          token_url_template = ?"https://explorer.aptoslabs.com/account/{token}?network=mainnet";
        };
      };
      case ("sui_mainnet") {
        ?{
          network = Types.SUI_MAINNET;
          address_url_template = "https://suiscan.xyz/mainnet/account/{address}";
          token_url_template = ?"https://suiscan.xyz/mainnet/coin/{token}";
        };
      };
      case (_) null;
    };
  };

  func normalize_config_network_name(network : Text) : Text {
    let trimmed = Text.trim(network, #predicate(func(c) = Char.isWhitespace(c)));
    let lower = Text.toLowercase(trimmed);
    Text.replace(lower, #char '-', "_");
  };
}

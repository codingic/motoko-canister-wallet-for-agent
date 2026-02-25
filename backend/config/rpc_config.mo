import Array "mo:base/Array";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Types "../types";

module {
  public let DEFAULT_SOLANA_RPC_URL : Text = "https://solana-rpc.publicnode.com";
  public let DEFAULT_SOLANA_TESTNET_RPC_URL : Text = "https://solana-testnet-rpc.publicnode.com";
  public let DEFAULT_ETHEREUM_RPC_URL : Text = "https://ethereum-rpc.publicnode.com";
  public let DEFAULT_SEPOLIA_RPC_URL : Text = "https://ethereum-sepolia-rpc.publicnode.com";
  public let DEFAULT_BASE_RPC_URL : Text = "https://base-rpc.publicnode.com";
  public let DEFAULT_POLYGON_RPC_URL : Text = "https://polygon-bor-rpc.publicnode.com";
  public let DEFAULT_ARBITRUM_RPC_URL : Text = "https://arbitrum-one-rpc.publicnode.com";
  public let DEFAULT_OPTIMISM_RPC_URL : Text = "https://optimism-rpc.publicnode.com";
  public let DEFAULT_BSC_RPC_URL : Text = "https://bsc-rpc.publicnode.com";
  public let DEFAULT_AVALANCHE_RPC_URL : Text = "https://avalanche-c-chain-rpc.publicnode.com";
  public let DEFAULT_OKX_RPC_URL : Text = "https://xlayerrpc.okx.com";
  public let DEFAULT_TRON_RPC_URL : Text = "https://tron-rpc.publicnode.com";
  public let DEFAULT_TON_RPC_URL : Text = "https://toncenter.com/api/v2";
  public let DEFAULT_NEAR_RPC_URL : Text = "https://rpc.mainnet.near.org";
  public let DEFAULT_APTOS_RPC_URL : Text = "https://fullnode.mainnet.aptoslabs.com/v1";
  public let DEFAULT_SUI_RPC_URL : Text = "https://fullnode.mainnet.sui.io:443";
  public let DEFAULT_BITCOIN_RPC_URL : Text = "https://blockstream.info/api";
  public let TEST_CUSTOM_RPC_URL : Text = "https://rpc.example";

  public type ChainConfig = {
    id : Text;
    primary_symbol : Text;
    address_family : Text;
    shared_address_group : Text;
    supports_send : Bool;
    supports_balance : Bool;
    default_rpc_url : ?Text;
    chain_id : ?Nat;
    wallet_visible : Bool;
  };

  public type WalletNetworkInfo = {
    id : Text;
    primary_symbol : Text;
    address_family : Text;
    shared_address_group : Text;
    supports_send : Bool;
    supports_balance : Bool;
    default_rpc_url : ?Text;
  };

  public type RpcConfig = {
    network : Text;
    rpc_url : Text;
  };

  let CHAIN_CONFIGS : [ChainConfig] = [
    {
      id = Types.BITCOIN;
      primary_symbol = "BTC";
      address_family = "bitcoin";
      shared_address_group = "btc-taproot-managed-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_BITCOIN_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.INTERNET_COMPUTER;
      primary_symbol = "ICP";
      address_family = "icp";
      shared_address_group = "icp-canister-principal-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = null;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.ETHEREUM;
      primary_symbol = "ETH";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_ETHEREUM_RPC_URL;
      chain_id = ?1;
      wallet_visible = true;
    },
    {
      id = Types.SEPOLIA;
      primary_symbol = "ETH";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_SEPOLIA_RPC_URL;
      chain_id = ?11155111;
      wallet_visible = true;
    },
    {
      id = Types.BASE;
      primary_symbol = "ETH";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_BASE_RPC_URL;
      chain_id = ?8453;
      wallet_visible = true;
    },
    {
      id = Types.POLYGON;
      primary_symbol = "POL";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_POLYGON_RPC_URL;
      chain_id = ?137;
      wallet_visible = true;
    },
    {
      id = Types.ARBITRUM;
      primary_symbol = "ETH";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_ARBITRUM_RPC_URL;
      chain_id = ?42161;
      wallet_visible = true;
    },
    {
      id = Types.OPTIMISM;
      primary_symbol = "ETH";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_OPTIMISM_RPC_URL;
      chain_id = ?10;
      wallet_visible = true;
    },
    {
      id = Types.BSC;
      primary_symbol = "BNB";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_BSC_RPC_URL;
      chain_id = ?56;
      wallet_visible = true;
    },
    {
      id = Types.AVALANCHE;
      primary_symbol = "AVAX";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_AVALANCHE_RPC_URL;
      chain_id = ?43114;
      wallet_visible = true;
    },
    {
      id = Types.OKX;
      primary_symbol = "OKB";
      address_family = "evm";
      shared_address_group = "evm-secp256k1-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_OKX_RPC_URL;
      chain_id = ?196;
      wallet_visible = true;
    },
    {
      id = Types.SOLANA;
      primary_symbol = "SOL";
      address_family = "solana";
      shared_address_group = "solana-ed25519-base58-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_SOLANA_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.SOLANA_TESTNET;
      primary_symbol = "SOL";
      address_family = "solana";
      shared_address_group = "solana-ed25519-base58-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_SOLANA_TESTNET_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.TRON;
      primary_symbol = "TRX";
      address_family = "tron";
      shared_address_group = "tron-secp256k1-base58check-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_TRON_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.TON_MAINNET;
      primary_symbol = "TON";
      address_family = "ton";
      shared_address_group = "ton-wallet-v4r2-ed25519-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_TON_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.NEAR_MAINNET;
      primary_symbol = "NEAR";
      address_family = "near";
      shared_address_group = "near-implicit-ed25519-hex-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_NEAR_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.APTOS_MAINNET;
      primary_symbol = "APT";
      address_family = "aptos";
      shared_address_group = "aptos-authkey-ed25519-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_APTOS_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
    {
      id = Types.SUI_MAINNET;
      primary_symbol = "SUI";
      address_family = "sui";
      shared_address_group = "sui-blake2b-ed25519-v1";
      supports_send = true;
      supports_balance = true;
      default_rpc_url = ?DEFAULT_SUI_RPC_URL;
      chain_id = null;
      wallet_visible = true;
    },
  ];

  public func supported_networks() : [Text] {
    Array.map<ChainConfig, Text>(
      Array.filter<ChainConfig>(CHAIN_CONFIGS, func(cfg) = cfg.chain_id != null),
      func(cfg) = cfg.id,
    );
  };

  public func wallet_networks() : [WalletNetworkInfo] {
    Array.map<ChainConfig, WalletNetworkInfo>(
      Array.filter<ChainConfig>(CHAIN_CONFIGS, func(cfg) = cfg.wallet_visible),
      chain_wallet_info,
    );
  };

  public func normalize_network(network : Text) : Text {
    let n = normalize_text(network);
    switch (find_chain_by_input(n)) {
      case (?cfg) cfg.id;
      case null n;
    };
  };

  public func wallet_network_info(network : Text) : ?WalletNetworkInfo {
    let normalized = normalize_text(network);
    if (normalized == "") {
      switch (find_chain_by_id(Types.INTERNET_COMPUTER)) {
        case (?cfg) ?chain_wallet_info(cfg);
        case null null;
      };
    } else {
      switch (find_wallet_chain_by_input(normalized)) {
        case (?cfg) ?chain_wallet_info(cfg);
        case null null;
      };
    };
  };

  public func configured_rpc(network : Text) : ?RpcConfig {
    switch (find_chain_by_input(normalize_text(network))) {
      case (?cfg) {
        switch (cfg.default_rpc_url) {
          case (?rpc_url) ?{ network = cfg.id; rpc_url };
          case null null;
        };
      };
      case null null;
    };
  };

  public func is_supported(network : Text) : Bool {
    wallet_network_info(network) != null or parse_custom_chain_id(network) != null;
  };

  public func chain_id(network : Text) : ?Nat {
    switch (find_chain_by_input(network)) {
      case (?cfg) cfg.chain_id;
      case null parse_custom_chain_id(network);
    };
  };

  public func default_rpc_url(network : Text) : ?Text {
    switch (find_chain_by_input(network)) {
      case (?cfg) cfg.default_rpc_url;
      case null null;
    };
  };

  public func effective_rpc_url(network : Text, rpc_url : ?Text) : ?Text {
    switch (effective_optional_url(rpc_url)) {
      case (?u) ?u;
      case null default_rpc_url(network);
    };
  };

  public func resolve_rpc_url(network : Text, rpc_url : ?Text) : Result.Result<Text, Text> {
    switch (effective_rpc_url(network, rpc_url)) {
      case (?u) #ok(u);
      case null {
        if (parse_custom_chain_id(network) != null) {
          #err("rpcUrl is required for custom network: " # network);
        } else {
          #err("unsupported network: " # network);
        };
      };
    };
  };

  public func effective_solana_rpc_url(rpc_url : ?Text) : Text {
    switch (effective_optional_url(rpc_url)) {
      case (?u) u;
      case null DEFAULT_SOLANA_RPC_URL;
    };
  };

  public func effective_solana_testnet_rpc_url(rpc_url : ?Text) : Text {
    switch (effective_optional_url(rpc_url)) {
      case (?u) u;
      case null DEFAULT_SOLANA_TESTNET_RPC_URL;
    };
  };

  func find_chain_by_id(network : Text) : ?ChainConfig {
    if (network == "") return null;
    Array.find<ChainConfig>(CHAIN_CONFIGS, func(cfg) = cfg.id == network);
  };

  func find_chain_by_input(network : Text) : ?ChainConfig {
    let normalized = normalize_text(network);
    find_chain_by_id(normalized);
  };

  func find_wallet_chain_by_input(network : Text) : ?ChainConfig {
    switch (find_chain_by_input(network)) {
      case (?cfg) {
        if (cfg.wallet_visible) ?cfg else null;
      };
      case null null;
    };
  };

  func chain_wallet_info(cfg : ChainConfig) : WalletNetworkInfo {
    {
      id = cfg.id;
      primary_symbol = cfg.primary_symbol;
      address_family = cfg.address_family;
      shared_address_group = cfg.shared_address_group;
      supports_send = cfg.supports_send;
      supports_balance = cfg.supports_balance;
      default_rpc_url = cfg.default_rpc_url;
    };
  };

  func normalize_text(value : Text) : Text {
    let trimmed = Text.trim(value, #predicate(func(c) = Char.isWhitespace(c)));
    let lower = Text.toLowercase(trimmed);
    Text.replace(lower, #char '-', "_");
  };

  func effective_optional_url(value : ?Text) : ?Text {
    switch (value) {
      case (null) null;
      case (?u) {
        let t = Text.trim(u, #predicate(func(c) = Char.isWhitespace(c)));
        if (t == "") null else ?t;
      };
    };
  };

  func parse_custom_chain_id(network : Text) : ?Nat {
    let n = normalize_network(network);
    let parts = Iter.toArray(Text.split(n, #char ':'));
    if (parts.size() != 2) return null;

    let prefix = parts[0];
    let chain_id_text = Text.trim(parts[1], #predicate(func(c) = Char.isWhitespace(c)));
    if (prefix != "eip155" and prefix != "chainid" and prefix != "evm") {
      return null;
    };

    switch (Nat.fromText(chain_id_text)) {
      case (?parsed) {
        if (parsed == 0) null else ?parsed;
      };
      case null null;
    };
  };
}

import Principal "mo:base/Principal";

module {
  public type Network = Text;

  public let BITCOIN : Network = "bitcoin";
  public let ETHEREUM : Network = "ethereum";
  public let SEPOLIA : Network = "sepolia";
  public let BASE : Network = "base";
  public let BSC : Network = "bsc";
  public let ARBITRUM : Network = "arbitrum";
  public let OPTIMISM : Network = "optimism";
  public let AVALANCHE : Network = "avalanche";
  public let OKX : Network = "okx";
  public let POLYGON : Network = "polygon";
  public let INTERNET_COMPUTER : Network = "internet_computer";
  public let SOLANA : Network = "solana";
  public let SOLANA_TESTNET : Network = "solana_testnet";
  public let TRON : Network = "tron";
  public let TON_MAINNET : Network = "ton_mainnet";
  public let NEAR_MAINNET : Network = "near_mainnet";
  public let APTOS_MAINNET : Network = "aptos_mainnet";
  public let SUI_MAINNET : Network = "sui_mainnet";

  public let WALLET_NETWORK_IDS : [Network] = [
    ETHEREUM,
    SEPOLIA,
    BASE,
    BSC,
    ARBITRUM,
    OPTIMISM,
    AVALANCHE,
    OKX,
    POLYGON,
    INTERNET_COMPUTER,
    BITCOIN,
    SOLANA,
    SOLANA_TESTNET,
    TRON,
    TON_MAINNET,
    NEAR_MAINNET,
    APTOS_MAINNET,
    SUI_MAINNET,
  ];

  public type AddressResponse = {
    network : Network;
    address : Text;
    public_key_hex : Text;
    key_name : Text;
    message : ?Text;
  };

  // Mirrors config/token_list_config.rs internal row type.
  public type ConfiguredTokenConfig = {
    network : Network;
    symbol : Text;
    name : Text;
    token_address : Text;
    decimals : Nat;
  };

  public type ConfiguredTokenResponse = {
    network : Network;
    symbol : Text;
    name : Text;
    token_address : Text;
    decimals : Nat;
  };

  public type AddConfiguredTokenRequest = {
    network : Network;
    token_address : Text;
  };

  public type RemoveConfiguredTokenRequest = {
    network : Network;
    token_address : Text;
  };

  public type ConfiguredRpcResponse = {
    network : Network;
    rpc_url : Text;
  };

  public type SetConfiguredRpcRequest = {
    network : Network;
    rpc_url : Text;
  };

  public type RemoveConfiguredRpcRequest = {
    network : Network;
  };

  public type ConfiguredExplorerResponse = {
    network : Network;
    address_url_template : Text;
    token_url_template : ?Text;
  };

  public type BalanceRequest = {
    account : Text;
    token : ?Text;
  };

  public type BalanceResponse = {
    network : Network;
    account : Text;
    token : ?Text;
    amount : ?Text;
    decimals : ?Nat8;
    block_ref : ?Text;
    pending : Bool;
    message : ?Text;
  };

  public type TransferRequest = {
    from : ?Text;
    to : Text;
    amount : Text;
    token : ?Text;
    memo : ?Text;
    nonce : ?Text;
    metadata : [(Text, Text)];
  };

  public type TransferResponse = {
    network : Network;
    accepted : Bool;
    tx_id : ?Text;
    message : Text;
  };

  public type NetworkModuleStatus = {
    network : Network;
    balance_ready : Bool;
    transfer_ready : Bool;
    note : ?Text;
  };

  public type WalletNetworkInfoResponse = {
    id : Network;
    primary_symbol : Text;
    address_family : Text;
    shared_address_group : Text;
    supports_send : Bool;
    supports_balance : Bool;
    default_rpc_url : ?Text;
  };

  public type ServiceInfoResponse = {
    version : Text;
    owner : ?Principal;
    paused : Bool;
    caller : Principal;
    note : ?Text;
  };
}

import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import CfgExplorer "./config/explorer_config";
import CfgRpc "./config/rpc_config";
import CfgTokenList "./config/token_list_config";
import Error "./error";
import State "./state";
import TokenRegistry "./token_registry";
import Types "./types";

module {
  public let API_VERSION : Text = "0.1.0";
  public let SERVICE_INFO_NOTE : Text = "Auth is placeholder. Multi-chain address, balance, and transfer paths are largely implemented.";
  public let SUPPORTED_NETWORKS_NOTE : Text = "Module readiness is partial and tracked per network.";

  public func ensure_not_paused(paused : Bool) : Error.WalletResult<()> {
    if (paused) {
      #Err(#Paused);
    } else {
      #Ok(());
    };
  };

  public func require_owner_placeholder(caller : Principal) : Error.WalletResult<()> {
    // TODO(auth): enforce caller == owner after the function layer is stable.
    ignore caller;
    #Ok(());
  };

  public func normalize_network_name_key(input : Text) : Text {
    TokenRegistry.normalize_network_name(input)
  };

  public func service_info(
    caller : Principal,
    owner : ?Principal,
    paused : Bool,
  ) : Types.ServiceInfoResponse {
    {
      version = API_VERSION;
      owner;
      paused;
      caller;
      note = ?SERVICE_INFO_NOTE;
    };
  };

  public func supported_networks() : [Types.NetworkModuleStatus] {
    Array.map<CfgRpc.WalletNetworkInfo, Types.NetworkModuleStatus>(
      CfgRpc.wallet_networks(),
      func(info : CfgRpc.WalletNetworkInfo) : Types.NetworkModuleStatus {
        let status = status_for_network(info.id);
        {
          network = info.id;
          balance_ready = status.balance_ready;
          transfer_ready = status.transfer_ready;
          note = status.note;
        }
      },
    );
  };

  public func wallet_networks() : [Types.WalletNetworkInfoResponse] {
    Array.map<CfgRpc.WalletNetworkInfo, Types.WalletNetworkInfoResponse>(
      CfgRpc.wallet_networks(),
      func(info : CfgRpc.WalletNetworkInfo) : Types.WalletNetworkInfoResponse {
        {
          id = info.id;
          primary_symbol = info.primary_symbol;
          address_family = info.address_family;
          shared_address_group = info.shared_address_group;
          supports_send = info.supports_send;
          supports_balance = info.supports_balance;
          default_rpc_url = info.default_rpc_url;
        };
      },
    );
  };

  public func configured_tokens(network : Text) : [Types.ConfiguredTokenResponse] {
    let request_network = normalize_network_name_key(network);
    Array.map<CfgTokenList.ConfiguredToken, Types.ConfiguredTokenResponse>(
      CfgTokenList.configured_tokens(network),
      func(t : CfgTokenList.ConfiguredToken) : Types.ConfiguredTokenResponse {
        {
          network = request_network;
          symbol = t.symbol;
          name = t.name;
          token_address = t.token_address;
          decimals = t.decimals;
        };
      },
    );
  };

  public func configured_tokens_with_state(
    network : Text,
    custom_tokens : [Types.ConfiguredTokenResponse],
    removed_tokens : [State.TokenKey],
  ) : [Types.ConfiguredTokenResponse] {
    let request_network = normalize_network_name_key(network);
    let merged = Buffer.Buffer<Types.ConfiguredTokenResponse>(16);

    func is_removed(token_address : Text) : Bool {
      for (k in removed_tokens.vals()) {
        if (k.network == request_network and k.token_address == token_address) {
          return true;
        };
      };
      false
    };

    for (t in configured_tokens(request_network).vals()) {
      if (not is_removed(t.token_address)) {
        merged.add(t);
      };
    };

    for (token in custom_tokens.vals()) {
      if (token.network != request_network) {
        // caller typically pre-filters, but keep this helper defensive.
      } else if (is_removed(token.token_address)) {
        // tombstone wins
      } else {
        var replaced = false;
        var i : Nat = 0;
        while (i < merged.size()) {
          let existing = merged.get(i);
          if (existing.token_address == token.token_address) {
            merged.put(i, token);
            replaced := true;
          };
          i += 1;
        };
        if (not replaced) {
          merged.add(token);
        };
      };
    };

    Buffer.toArray(merged)
  };

  public func configured_explorer(network : Text) : ?Types.ConfiguredExplorerResponse {
    let request_network = normalize_network_name_key(network);
    switch (CfgExplorer.configured_explorer(network)) {
      case (?c) {
        ?{
          network = request_network;
          address_url_template = c.address_url_template;
          token_url_template = c.token_url_template;
        };
      };
      case null null;
    };
  };

  func status_for_network(network : Text) : {
    balance_ready : Bool;
    transfer_ready : Bool;
    note : ?Text;
  } {
    if (network == Types.INTERNET_COMPUTER) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"ICP/ICRC balance and transfer implemented";
      }
    } else if (network == Types.BITCOIN) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"BTC Taproot (P2TR key-path) address, balance, and transfer implemented";
      }
    } else if (
      network == Types.ETHEREUM or
      network == Types.SEPOLIA or
      network == Types.BASE or
      network == Types.BSC or
      network == Types.ARBITRUM or
      network == Types.OPTIMISM or
      network == Types.AVALANCHE or
      network == Types.OKX or
      network == Types.POLYGON
    ) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"EVM native/ERC20 address, balance, and transfer implemented";
      }
    } else if (network == Types.SOLANA or network == Types.SOLANA_TESTNET) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"SOL/SPL address, balance, and transfer implemented (SPL auto-creates destination ATA when missing)";
      }
    } else if (network == Types.TRON) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"TRX/TRC20 address, balance, and transfer implemented";
      }
    } else if (network == Types.TON_MAINNET) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"TON/Jetton balance and transfer implemented";
      }
    } else if (network == Types.NEAR_MAINNET) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"NEAR/NEP-141 address, balance, and transfer implemented";
      }
    } else if (network == Types.APTOS_MAINNET) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"Aptos address, balance, and transfer implemented";
      }
    } else if (network == Types.SUI_MAINNET) {
      {
        balance_ready = true;
        transfer_ready = true;
        note = ?"Sui address, balance, and transfer implemented";
      }
    } else {
      {
        balance_ready = false;
        transfer_ready = false;
        note = ?SUPPORTED_NETWORKS_NOTE;
      }
    }
  };
}

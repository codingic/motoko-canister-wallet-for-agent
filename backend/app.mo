import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import _Addressing "./addressing";
import _Aptos "./aptos_mainnet";
import Api "./api";
import _Btc "./bitcoin";
import CfgRpc "./config/rpc_config";
import _EvmRpc "./evm_rpc";
import Error "./error";
import Eth "./ethereum";
import Icp "./internet_computer";
import _Near "./near_mainnet";
import _Outcall "./outcall";
import Sepolia "./sepolia";
import _Sol "./solana";
import _SolanaTestnet "./solana_testnet";
import _Sui "./sui_mainnet";
import State "./state";
import _Ton "./ton_mainnet";
import _Trx "./tron";
import TokenRegistry "./token_registry";
import Types "./types";

persistent actor WalletBackend {
  public type WalletError = {
    #InvalidInput : Text;
    #Internal : Text;
    #Forbidden;
    #Paused;
    #Unimplemented : {
      network : Text;
      operation : Text;
    };
  };

  public type Result<Ok, Err> = {
    #Ok : Ok;
    #Err : Err;
  };

  public type NetworkSupportRow = {
    network : Text;
    balance_ready : Bool;
    transfer_ready : Bool;
    note : ?Text;
  };

  public type WalletNetworkRow = {
    id : Text;
    primary_symbol : Text;
    address_family : Text;
    shared_address_group : Text;
    supports_send : Bool;
    supports_balance : Bool;
    default_rpc_url : ?Text;
  };

  public type ConfiguredToken = {
    network : Text;
    symbol : Text;
    name : Text;
    token_address : Text;
    decimals : Nat8;
  };

  public type ConfiguredRpc = {
    network : Text;
    rpc_url : Text;
  };

  public type ConfiguredExplorer = {
    network : Text;
    address_url_template : Text;
    token_url_template : ?Text;
  };

  public type AddConfiguredTokenRequest = {
    network : Text;
    token_address : Text;
  };

  public type RemoveConfiguredTokenRequest = {
    network : Text;
    token_address : Text;
  };

  public type SetConfiguredRpcRequest = {
    network : Text;
    rpc_url : Text;
  };

  public type RemoveConfiguredRpcRequest = {
    network : Text;
  };

  public type ServiceInfo = {
    version : Text;
    owner : ?Principal;
    paused : Bool;
    caller : Principal;
    note : ?Text;
  };

  public type BalanceRequest = {
    account : Text;
    token : ?Text;
  };

  public type BalanceResponse = {
    network : Text;
    account : Text;
    token : ?Text;
    amount : ?Text;
    decimals : ?Nat8;
    pending : Bool;
    block_ref : ?Text;
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
    network : Text;
    accepted : Bool;
    tx_id : ?Text;
    message : Text;
  };

  public type AddressResponse = {
    network : Text;
    address : Text;
    public_key_hex : Text;
    key_name : Text;
    message : ?Text;
  };

  type WalletResult<T> = Result<T, WalletError>;
  type AssetKind = { #native; #token };

  var state_ : State.State = State.default();
  var note_ : ?Text = ?"Motoko compatibility backend for wallet-for-agent frontend";

  let STUB_NOTE : Text = "Motoko stub: external chain RPC/signer integration not connected yet";

  func mkToken(
    network : Text,
    symbol : Text,
    name : Text,
    tokenAddress : Text,
    decimals : Nat8,
  ) : ConfiguredToken {
    {
      network;
      symbol;
      name;
      token_address = tokenAddress;
      decimals;
    };
  };

  func mkExplorer(
    network : Text,
    addressUrlTemplate : Text,
    tokenUrlTemplate : ?Text,
  ) : ConfiguredExplorer {
    {
      network;
      address_url_template = addressUrlTemplate;
      token_url_template = tokenUrlTemplate;
    };
  };

  func mkRpc(network : Text, rpcUrl : Text) : ConfiguredRpc {
    { network; rpc_url = rpcUrl }
  };

  func walletNetworksRows() : [WalletNetworkRow] {
    Array.map<Types.WalletNetworkInfoResponse, WalletNetworkRow>(
      Api.wallet_networks(),
      func(row : Types.WalletNetworkInfoResponse) : WalletNetworkRow {
        {
          id = row.id;
          primary_symbol = row.primary_symbol;
          address_family = row.address_family;
          shared_address_group = row.shared_address_group;
          supports_send = row.supports_send;
          supports_balance = row.supports_balance;
          default_rpc_url = switch (State.configured_rpc(state_, row.id)) {
            case (?overrideUrl) ?overrideUrl;
            case null row.default_rpc_url;
          };
        };
      },
    )
  };

  func configuredRpcRows() : [ConfiguredRpc] {
    Array.map<Types.ConfiguredRpcResponse, ConfiguredRpc>(
      State.configured_rpcs(state_),
      func(row : Types.ConfiguredRpcResponse) : ConfiguredRpc {
        mkRpc(row.network, row.rpc_url)
      },
    )
  };

  let SUPPORTED_NETWORKS : [NetworkSupportRow] = Array.map<Types.NetworkModuleStatus, NetworkSupportRow>(
    Api.supported_networks(),
    func(row : Types.NetworkModuleStatus) : NetworkSupportRow {
      {
        network = row.network;
        balance_ready = row.balance_ready;
        transfer_ready = row.transfer_ready;
        note = row.note;
      };
    },
  );

  func optTextNonEmpty(v : ?Text) : ?Text {
    switch (v) {
      case (null) null;
      case (?t) {
        if (Text.size(t) == 0) {
          null;
        } else {
          ?t;
        };
      };
    };
  };

  func requireNonEmpty(name : Text, value : Text) : ?WalletError {
    if (Text.size(value) == 0) {
      ?(#InvalidInput(name # " is required"));
    } else {
      null;
    };
  };

  func requireOwnerPlaceholder(caller : Principal) : ?WalletError {
    switch (Api.require_owner_placeholder(caller)) {
      case (#Ok(())) null;
      case (#Err(#Forbidden)) ?#Forbidden;
      case (#Err(#Paused)) ?#Paused;
      case (#Err(#InvalidInput(msg))) ?#InvalidInput(msg);
      case (#Err(#Unimplemented(payload))) ?#Unimplemented(payload);
      case (#Err(#Internal(msg))) ?#Internal(msg);
    };
  };

  func fromError(err : Error.WalletError) : WalletError {
    switch (err) {
      case (#Forbidden) #Forbidden;
      case (#Paused) #Paused;
      case (#InvalidInput(msg)) #InvalidInput(msg);
      case (#Unimplemented(payload)) #Unimplemented(payload);
      case (#Internal(msg)) #Internal(msg);
    };
  };

  func fromTypesAddressResponse(resp : Types.AddressResponse) : AddressResponse {
    {
      network = resp.network;
      address = resp.address;
      public_key_hex = resp.public_key_hex;
      key_name = resp.key_name;
      message = resp.message;
    };
  };

  func fromTypesAddressResult(res : Error.WalletResult<Types.AddressResponse>) : WalletResult<AddressResponse> {
    switch (res) {
      case (#Ok(resp)) #Ok(fromTypesAddressResponse(resp));
      case (#Err(err)) #Err(fromError(err));
    };
  };

  func fromTypesBalanceResponse(resp : Types.BalanceResponse) : BalanceResponse {
    {
      network = resp.network;
      account = resp.account;
      token = resp.token;
      amount = resp.amount;
      decimals = resp.decimals;
      block_ref = resp.block_ref;
      pending = resp.pending;
      message = resp.message;
    };
  };

  func fromTypesBalanceResult(res : Error.WalletResult<Types.BalanceResponse>) : WalletResult<BalanceResponse> {
    switch (res) {
      case (#Ok(resp)) #Ok(fromTypesBalanceResponse(resp));
      case (#Err(err)) #Err(fromError(err));
    };
  };

  func rpcOverrideFor(network : Text) : ?Text {
    State.configured_rpc(state_, CfgRpc.normalize_network(network))
  };

  func evmNativeBalance(network : Text, req : BalanceRequest) : async WalletResult<BalanceResponse> {
    fromTypesBalanceResult(await _EvmRpc.get_native_balance_with_rpc(network, rpcOverrideFor(network), {
      account = req.account;
      token = req.token;
    }))
  };

  func evmTokenBalance(network : Text, req : BalanceRequest) : async WalletResult<BalanceResponse> {
    fromTypesBalanceResult(await _EvmRpc.get_erc20_balance_with_rpc(network, rpcOverrideFor(network), {
      account = req.account;
      token = req.token;
    }))
  };

  func fromTypesTransferResponse(resp : Types.TransferResponse) : TransferResponse {
    {
      network = resp.network;
      accepted = resp.accepted;
      tx_id = resp.tx_id;
      message = resp.message;
    };
  };

  func fromTypesTransferResult(res : Error.WalletResult<Types.TransferResponse>) : WalletResult<TransferResponse> {
    switch (res) {
      case (#Ok(resp)) #Ok(fromTypesTransferResponse(resp));
      case (#Err(err)) #Err(fromError(err));
    };
  };

  func evmNativeTransfer(network : Text, req : TransferRequest) : async WalletResult<TransferResponse> {
    fromTypesTransferResult(await _EvmRpc.transfer_native_with_rpc(network, rpcOverrideFor(network), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };

  func evmTokenTransfer(network : Text, req : TransferRequest) : async WalletResult<TransferResponse> {
    fromTypesTransferResult(await _EvmRpc.transfer_erc20_with_rpc(network, rpcOverrideFor(network), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };

  func trimmedOptTextNonEmpty(v : ?Text) : ?Text {
    switch (v) {
      case null null;
      case (?t0) {
        let t = Text.trim(t0, #char ' ');
        if (Text.size(t) == 0) null else ?t
      };
    }
  };

  func requireNativeTransferMethodTokenAbsent(methodName : Text, req : TransferRequest) : ?WalletError {
    switch (trimmedOptTextNonEmpty(req.token)) {
      case (?_) ?(#InvalidInput(methodName # " does not accept token parameter"));
      case null null;
    }
  };

  func requireTokenTransferMethodTokenPresent(methodName : Text, req : TransferRequest) : ?WalletError {
    switch (trimmedOptTextNonEmpty(req.token)) {
      case (?_) null;
      case null ?(#InvalidInput("token is required for " # methodName));
    }
  };

  func isPaused() : Bool { State.is_paused(state_) };

  func nativeDecimalsFor(network : Text) : Nat8 {
    switch (network) {
      case ("bitcoin") 8;
      case ("internet_computer") 8;
      case ("solana") 9;
      case ("solana_testnet") 9;
      case ("tron") 6;
      case ("ton_mainnet") 9;
      case ("near_mainnet") 24;
      case ("aptos_mainnet") 8;
      case ("sui_mainnet") 9;
      case (_) 18;
    };
  };

  func configuredTokensFor(network : Text) : [ConfiguredToken] {
    Array.map<Types.ConfiguredTokenResponse, ConfiguredToken>(
      Api.configured_tokens_with_state(
        network,
        State.custom_tokens_for_network(state_, Api.normalize_network_name_key(network)),
        State.removed_tokens(state_),
      ),
      func(row : Types.ConfiguredTokenResponse) : ConfiguredToken {
        mkToken(
          row.network,
          row.symbol,
          row.name,
          row.token_address,
          Nat8.fromNat(row.decimals),
        );
      },
    );
  };

  func configuredExplorerFor(network : Text) : ?ConfiguredExplorer {
    switch (Api.configured_explorer(network)) {
      case (?cfg) {
        ?mkExplorer(cfg.network, cfg.address_url_template, cfg.token_url_template);
      };
      case null null;
    };
  };

  func findConfiguredToken(network : Text, tokenAddress : Text) : ?ConfiguredToken {
    let rows = configuredTokensFor(network);
    for (row in rows.vals()) {
      if (row.token_address == tokenAddress) {
        return ?row;
      };
    };
    null;
  };

  func balanceDecimals(network : Text, kind : AssetKind, token : ?Text) : ?Nat8 {
    switch (kind) {
      case (#native) { ?nativeDecimalsFor(network) };
      case (#token) {
        switch (token) {
          case (null) null;
          case (?tokenAddress) {
            switch (findConfiguredToken(network, tokenAddress)) {
              case (?row) ?row.decimals;
              case null {
                switch (network) {
                  case ("bitcoin") ?8;
                  case ("tron") ?6;
                  case ("near_mainnet") ?24;
                  case (_) ?18;
                };
              };
            };
          };
        };
      };
    };
  };

  func _balanceImpl(
    caller : Principal,
    network : Text,
    kind : AssetKind,
    req : BalanceRequest,
  ) : WalletResult<BalanceResponse> {
    ignore caller;

    if (isPaused()) {
      return #Err(#Paused);
    };

    switch (requireNonEmpty("account", req.account)) {
      case (?err) return #Err(err);
      case null {};
    };

    let tokenOpt = optTextNonEmpty(req.token);
    if (kind == #token and tokenOpt == null) {
      return #Err(#InvalidInput("token is required for token balance query"));
    };

    let seed = network # "|" # req.account # "|" # (switch (tokenOpt) { case (?t) t; case null "" });
    let amountText = Nat32.toText(Text.hash(seed # ":amount"));

    #Ok({
      network;
      account = req.account;
      token = tokenOpt;
      amount = ?amountText;
      decimals = balanceDecimals(network, kind, tokenOpt);
      pending = true;
      block_ref = ?("mock:" # Nat32.toText(Text.hash(seed # ":block")));
      message = ?STUB_NOTE;
    });
  };

  func transferOperation(kind : AssetKind) : Text {
    switch (kind) {
      case (#native) "transfer_native";
      case (#token) "transfer_token";
    };
  };

  func _transferImpl(
    caller : Principal,
    network : Text,
    kind : AssetKind,
    req : TransferRequest,
  ) : WalletResult<TransferResponse> {
    ignore caller;

    if (isPaused()) {
      return #Err(#Paused);
    };

    switch (requireNonEmpty("to", req.to)) {
      case (?err) return #Err(err);
      case null {};
    };
    switch (requireNonEmpty("amount", req.amount)) {
      case (?err) return #Err(err);
      case null {};
    };

    let tokenOpt = optTextNonEmpty(req.token);
    if (kind == #token and tokenOpt == null) {
      return #Err(#InvalidInput("token is required for token transfer"));
    };

    #Err(
      #Unimplemented({
        network;
        operation = transferOperation(kind);
      })
    );
  };

  public shared query ({ caller }) func whoami() : async Principal {
    caller;
  };

  public query func get_owner() : async ?Principal {
    State.owner(state_);
  };

  public query func is_paused() : async Bool {
    State.is_paused(state_);
  };

  public shared ({ caller }) func rotate_owner(new_owner : Principal) : async WalletResult<?Principal> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };
    if (Principal.isAnonymous(new_owner)) {
      return #Err(#InvalidInput("new_owner cannot be anonymous"));
    };

    let (prev, nextState) = State.rotate_owner(state_, new_owner);
    state_ := nextState;
    #Ok(prev);
  };

  public shared ({ caller }) func pause() : async WalletResult<()> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };
    state_ := State.set_paused(state_, true);
    #Ok(());
  };

  public shared ({ caller }) func unpause() : async WalletResult<()> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };
    state_ := State.set_paused(state_, false);
    #Ok(());
  };

  public shared query ({ caller }) func service_info() : async ServiceInfo {
    let base = Api.service_info(caller, State.owner(state_), State.is_paused(state_));
    {
      version = base.version;
      owner = base.owner;
      paused = base.paused;
      caller = base.caller;
      note = switch (note_) {
        case (?n) ?n;
        case null base.note;
      };
    };
  };

  public query func supported_networks() : async [NetworkSupportRow] {
    SUPPORTED_NETWORKS;
  };

  public query func wallet_networks() : async [WalletNetworkRow] {
    walletNetworksRows();
  };

  public query func configured_rpcs() : async [ConfiguredRpc] {
    configuredRpcRows();
  };

  public query func configured_tokens(network : Text) : async [ConfiguredToken] {
    configuredTokensFor(network);
  };

  public query func configured_explorer(network : Text) : async ?ConfiguredExplorer {
    configuredExplorerFor(network);
  };

  public shared ({ caller }) func add_configured_token(req : AddConfiguredTokenRequest) : async WalletResult<ConfiguredToken> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };
    if (isPaused()) {
      return #Err(#Paused);
    };

    let discovered = switch (await TokenRegistry.discover_token_metadata(req.network, req.token_address)) {
      case (#Err(err)) return #Err(fromError(err));
      case (#Ok(v)) v;
    };

    let normalizedNetwork = Api.normalize_network_name_key(req.network);
    let tokenRow : Types.ConfiguredTokenResponse = {
      network = normalizedNetwork;
      symbol = discovered.symbol;
      name = discovered.name;
      token_address = discovered.token_address;
      decimals = discovered.decimals;
    };
    let (_, nextState) = State.upsert_custom_token(state_, tokenRow);
    state_ := nextState;

    #Ok(
      mkToken(
        tokenRow.network,
        tokenRow.symbol,
        tokenRow.name,
        tokenRow.token_address,
        Nat8.fromNat(tokenRow.decimals),
      )
    )
  };

  public shared ({ caller }) func remove_configured_token(req : RemoveConfiguredTokenRequest) : async WalletResult<Bool> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };

    let network = Api.normalize_network_name_key(req.network);
    let tokenAddress = Text.trim(req.token_address, #char ' ');
    if (Text.size(tokenAddress) == 0) {
      return #Err(#InvalidInput("token_address is required"));
    };

    let (changed, nextState) = State.remove_token(state_, network, tokenAddress);
    state_ := nextState;
    #Ok(changed)
  };

  public shared ({ caller }) func set_configured_rpc(req : SetConfiguredRpcRequest) : async WalletResult<ConfiguredRpc> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };

    let network = CfgRpc.normalize_network(req.network);
    if (Text.size(network) == 0) {
      return #Err(#InvalidInput("network is required"));
    };
    if (CfgRpc.wallet_network_info(network) == null) {
      return #Err(#InvalidInput("unsupported network"));
    };

    let rpcUrl = Text.trim(req.rpc_url, #char ' ');
    if (Text.size(rpcUrl) == 0) {
      return #Err(#InvalidInput("rpc_url is required"));
    };

    let rpcRow : Types.ConfiguredRpcResponse = { network; rpc_url = rpcUrl };
    let (_, nextState) = State.upsert_configured_rpc(state_, network, rpcUrl);
    state_ := nextState;
    #Ok(mkRpc(rpcRow.network, rpcRow.rpc_url))
  };

  public shared ({ caller }) func remove_configured_rpc(req : RemoveConfiguredRpcRequest) : async WalletResult<Bool> {
    switch (requireOwnerPlaceholder(caller)) {
      case (?err) return #Err(err);
      case null {};
    };

    let network = CfgRpc.normalize_network(req.network);
    if (Text.size(network) == 0) {
      return #Err(#InvalidInput("network is required"));
    };

    let (removed, nextState) = State.remove_configured_rpc(state_, network);
    state_ := nextState;
    #Ok(removed)
  };

  public shared ({ caller }) func ethereum_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address())
  };
  public shared ({ caller }) func sepolia_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Sepolia.request_address())
  };
  public shared ({ caller }) func base_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("base"))
  };
  public shared ({ caller }) func bsc_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("bsc"))
  };
  public shared ({ caller }) func arbitrum_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("arbitrum"))
  };
  public shared ({ caller }) func optimism_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("optimism"))
  };
  public shared ({ caller }) func avalanche_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("avalanche"))
  };
  public shared ({ caller }) func okx_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("okx"))
  };
  public shared ({ caller }) func polygon_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await Eth.request_address_for_network("polygon"))
  };
  public shared ({ caller }) func bitcoin_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Btc.request_address())
  };
  public shared ({ caller }) func solana_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Sol.request_address())
  };
  public shared ({ caller }) func solana_testnet_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _SolanaTestnet.request_address())
  };
  public shared ({ caller }) func tron_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Trx.request_address())
  };
  public shared ({ caller }) func ton_mainnet_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Ton.request_address())
  };
  public shared ({ caller }) func near_mainnet_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Near.request_address())
  };
  public shared ({ caller }) func aptos_mainnet_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Aptos.request_address())
  };
  public shared ({ caller }) func sui_mainnet_request_address() : async WalletResult<AddressResponse> {
    ignore caller;
    fromTypesAddressResult(await _Sui.request_address())
  };

  public shared ({ caller }) func ethereum_get_balance_eth(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("ethereum", req) };
  public shared ({ caller }) func ethereum_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("ethereum", req) };
  public shared ({ caller }) func sepolia_get_balance_eth(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("sepolia", req) };
  public shared ({ caller }) func sepolia_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("sepolia", req) };
  public shared ({ caller }) func base_get_balance_eth(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("base", req) };
  public shared ({ caller }) func base_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("base", req) };
  public shared ({ caller }) func bsc_get_balance_bnb(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("bsc", req) };
  public shared ({ caller }) func bsc_get_balance_bep20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("bsc", req) };
  public shared ({ caller }) func arbitrum_get_balance_eth(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("arbitrum", req) };
  public shared ({ caller }) func arbitrum_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("arbitrum", req) };
  public shared ({ caller }) func optimism_get_balance_eth(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("optimism", req) };
  public shared ({ caller }) func optimism_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("optimism", req) };
  public shared ({ caller }) func avalanche_get_balance_avax(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("avalanche", req) };
  public shared ({ caller }) func avalanche_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("avalanche", req) };
  public shared ({ caller }) func okx_get_balance_okb(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("okx", req) };
  public shared ({ caller }) func okx_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("okx", req) };
  public shared ({ caller }) func polygon_get_balance_pol(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmNativeBalance("polygon", req) };
  public shared ({ caller }) func polygon_get_balance_erc20(req : BalanceRequest) : async WalletResult<BalanceResponse> { ignore caller; await evmTokenBalance("polygon", req) };
  public shared ({ caller }) func bitcoin_get_balance_btc(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Btc.get_balance_with_rpc(rpcOverrideFor("bitcoin"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func internet_computer_get_balance_icp(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await Icp.get_balance_icp({
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func internet_computer_get_balance_icrc(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await Icp.get_balance_icrc({
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func solana_get_balance_sol(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Sol.get_balance_for_network_with_rpc("solana", rpcOverrideFor("solana"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func solana_get_balance_spl(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Sol.get_balance_for_network_with_rpc("solana", rpcOverrideFor("solana"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func solana_testnet_get_balance_sol(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _SolanaTestnet.get_balance_with_rpc(rpcOverrideFor("solana_testnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func solana_testnet_get_balance_spl(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _SolanaTestnet.get_balance_with_rpc(rpcOverrideFor("solana_testnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func tron_get_balance_trx(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Trx.get_balance_with_rpc(rpcOverrideFor("tron"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func tron_get_balance_trc20(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Trx.get_balance_with_rpc(rpcOverrideFor("tron"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func ton_mainnet_get_balance_ton(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Ton.get_balance_with_rpc(rpcOverrideFor("ton_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func ton_mainnet_get_balance_jetton(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Ton.get_balance_with_rpc(rpcOverrideFor("ton_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func near_mainnet_get_balance_near(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Near.get_balance_with_rpc(rpcOverrideFor("near_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func near_mainnet_get_balance_nep141(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Near.get_balance_with_rpc(rpcOverrideFor("near_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func aptos_mainnet_get_balance_apt(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Aptos.get_balance_with_rpc(rpcOverrideFor("aptos_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func aptos_mainnet_get_balance_token(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Aptos.get_balance_with_rpc(rpcOverrideFor("aptos_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func sui_mainnet_get_balance_sui(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Sui.get_balance_with_rpc(rpcOverrideFor("sui_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };
  public shared ({ caller }) func sui_mainnet_get_balance_token(req : BalanceRequest) : async WalletResult<BalanceResponse> {
    ignore caller;
    fromTypesBalanceResult(await _Sui.get_balance_with_rpc(rpcOverrideFor("sui_mainnet"), {
      account = req.account;
      token = req.token;
    }))
  };

  public shared ({ caller }) func ethereum_transfer_eth(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("ethereum", req) };
  public shared ({ caller }) func ethereum_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("ethereum", req) };
  public shared ({ caller }) func sepolia_transfer_eth(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("sepolia", req) };
  public shared ({ caller }) func sepolia_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("sepolia", req) };
  public shared ({ caller }) func base_transfer_eth(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("base", req) };
  public shared ({ caller }) func base_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("base", req) };
  public shared ({ caller }) func bsc_transfer_bnb(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("bsc", req) };
  public shared ({ caller }) func bsc_transfer_bep20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("bsc", req) };
  public shared ({ caller }) func arbitrum_transfer_eth(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("arbitrum", req) };
  public shared ({ caller }) func arbitrum_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("arbitrum", req) };
  public shared ({ caller }) func optimism_transfer_eth(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("optimism", req) };
  public shared ({ caller }) func optimism_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("optimism", req) };
  public shared ({ caller }) func avalanche_transfer_avax(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("avalanche", req) };
  public shared ({ caller }) func avalanche_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("avalanche", req) };
  public shared ({ caller }) func okx_transfer_okb(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("okx", req) };
  public shared ({ caller }) func okx_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("okx", req) };
  public shared ({ caller }) func polygon_transfer_pol(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmNativeTransfer("polygon", req) };
  public shared ({ caller }) func polygon_transfer_erc20(req : TransferRequest) : async WalletResult<TransferResponse> { ignore caller; await evmTokenTransfer("polygon", req) };
  public shared ({ caller }) func internet_computer_transfer_icp(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await Icp.transfer_icp({
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func internet_computer_transfer_icrc(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await Icp.transfer_icrc({
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func bitcoin_transfer_btc(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Btc.transfer_with_rpc(rpcOverrideFor("bitcoin"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func solana_transfer_sol(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Sol.transfer_sol_for_network_with_rpc("solana", rpcOverrideFor("solana"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func solana_transfer_spl(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Sol.transfer_spl_for_network_with_rpc("solana", rpcOverrideFor("solana"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func solana_testnet_transfer_sol(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _SolanaTestnet.transfer_sol_with_rpc(rpcOverrideFor("solana_testnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func solana_testnet_transfer_spl(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _SolanaTestnet.transfer_spl_with_rpc(rpcOverrideFor("solana_testnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func tron_transfer_trx(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    switch (requireNativeTransferMethodTokenAbsent("tron_transfer_trx", req)) {
      case (?err) return #Err(err);
      case null {};
    };
    fromTypesTransferResult(await _Trx.transfer_with_rpc(rpcOverrideFor("tron"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func tron_transfer_trc20(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    switch (requireTokenTransferMethodTokenPresent("tron_transfer_trc20", req)) {
      case (?err) return #Err(err);
      case null {};
    };
    fromTypesTransferResult(await _Trx.transfer_with_rpc(rpcOverrideFor("tron"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func ton_mainnet_transfer_ton(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Ton.transfer_ton_with_rpc(rpcOverrideFor("ton_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func ton_mainnet_transfer_jetton(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Ton.transfer_jetton_with_rpc(rpcOverrideFor("ton_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func near_mainnet_transfer_near(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    switch (requireNativeTransferMethodTokenAbsent("near_mainnet_transfer_near", req)) {
      case (?err) return #Err(err);
      case null {};
    };
    fromTypesTransferResult(await _Near.transfer_with_rpc(rpcOverrideFor("near_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func near_mainnet_transfer_nep141(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    switch (requireTokenTransferMethodTokenPresent("near_mainnet_transfer_nep141", req)) {
      case (?err) return #Err(err);
      case null {};
    };
    fromTypesTransferResult(await _Near.transfer_with_rpc(rpcOverrideFor("near_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func aptos_mainnet_transfer_apt(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    switch (requireNativeTransferMethodTokenAbsent("aptos_mainnet_transfer_apt", req)) {
      case (?err) return #Err(err);
      case null {};
    };
    fromTypesTransferResult(await _Aptos.transfer_with_rpc(rpcOverrideFor("aptos_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func aptos_mainnet_transfer_token(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    switch (requireTokenTransferMethodTokenPresent("aptos_mainnet_transfer_token", req)) {
      case (?err) return #Err(err);
      case null {};
    };
    fromTypesTransferResult(await _Aptos.transfer_with_rpc(rpcOverrideFor("aptos_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func sui_mainnet_transfer_sui(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Sui.transfer_sui_with_rpc(rpcOverrideFor("sui_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
  public shared ({ caller }) func sui_mainnet_transfer_token(req : TransferRequest) : async WalletResult<TransferResponse> {
    ignore caller;
    fromTypesTransferResult(await _Sui.transfer_token_with_rpc(rpcOverrideFor("sui_mainnet"), {
      from = req.from;
      to = req.to;
      amount = req.amount;
      token = req.token;
      memo = req.memo;
      nonce = req.nonce;
      metadata = req.metadata;
    }))
  };
};

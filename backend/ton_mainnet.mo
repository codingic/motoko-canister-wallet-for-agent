import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import MoError "mo:base/Error";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Addressing "./addressing";
import AppConfig "./config/app_config";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import TonTx "./sdk/ton_tx";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.TON_MAINNET;
  let TON_DECIMALS : Nat8 = 9;
  let TON_WALLET_MODE_DEFAULT : Nat8 = 3;
  let TON_VALID_UNTIL_SECS_AHEAD : Nat = 300;
  let TON_JETTON_FORWARD_AMOUNT_NANOTON : Nat = 1;
  let TON_JETTON_ATTACHED_NANOTON_DEFAULT : Nat = 100_000_000; // 0.1 TON

  type SchnorrKeyId = {
    algorithm : Addressing.SchnorrAlgorithm;
    name : Text;
  };

  type SignWithSchnorrArgs = {
    message : Blob;
    derivation_path : [Blob];
    key_id : SchnorrKeyId;
    aux : ?Blob;
  };

  type SignWithSchnorrResult = {
    signature : Blob;
  };

  let Management : actor {
    sign_with_schnorr : shared (SignWithSchnorrArgs) -> async SignWithSchnorrResult;
  } = actor "aaaaa-aa";

  type ManagedTonWallet = {
    address : TonTx.TonAddress;
    state_init : TonTx.Cell;
  };

  type TonWalletState = {
    seqno : Nat32;
    active : Bool;
  };

  type JettonWalletInfo = {
    address : TonTx.TonAddress;
    address_text : Text;
    balance : Nat;
  };

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((pubkey, key_name))) {
        if (pubkey.size() != 32) {
          return #Err(#Internal("unexpected ed25519 public key length for TON address: " # Nat.toText(pubkey.size())));
        };
        let code = switch (TonTx.wallet_v4r2_code_cell()) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let data = switch (TonTx.wallet_v4r2_data_cell(pubkey, TonTx.TON_WALLET_V4R2_WALLET_ID)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let stateInit = switch (TonTx.state_init_cell(code, data)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let rawAddr = TonTx.contract_address_from_state_init(stateInit, TonTx.TON_WORKCHAIN_BASECHAIN);
        let address = TonTx.format_user_friendly_address(rawAddr, false, false);
        #Ok({
          network = NETWORK_NAME;
          address;
          public_key_hex = Addressing.hex_encode(pubkey);
          key_name;
          message = ?"TON wallet v4r2 address from management canister Schnorr(ed25519) public key";
        })
      };
    }
  };

  public func get_balance(req : Types.BalanceRequest) : async Error.WalletResult<Types.BalanceResponse> {
    await get_balance_with_rpc(null, req)
  };

  public func get_balance_with_rpc(
    rpcOverride : ?Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    let accountAddr = switch (TonTx.parse_ton_address(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let account = TonTx.format_user_friendly_address(accountAddr, false, false);
    let tokenOpt = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) null else ?trimmed;
      };
      case null null;
    };
    switch (tokenOpt) {
      case (?tokenMasterRaw) {
        let tokenMasterAddr = switch (TonTx.parse_ton_address(tokenMasterRaw)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let tokenMaster = TonTx.format_user_friendly_address(tokenMasterAddr, false, false);
        let walletLookup = switch (await ton_v3_get_json(
          "/jetton/wallets?owner_address=" # percent_encode(account) #
          "&jetton_address=" # percent_encode(tokenMaster) #
          "&limit=1&offset=0",
          rpcOverride,
        )) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let decimals = switch (await fetch_jetton_decimals_from_v3(tokenMaster, rpcOverride)) {
          case (?v) v;
          case null TON_DECIMALS;
        };
        let (amountRaw, walletTextOpt) = switch (first_jetton_wallet(walletLookup)) {
          case (?walletObj) {
            let amount = switch (json_nat_field(walletObj, "balance")) {
              case (?v) v;
              case null 0;
            };
            let walletText = switch (json_string_field(walletObj, "address")) {
              case (?s) ?s;
              case null json_string_field(walletObj, "wallet_address");
            };
            (amount, walletText)
          };
          case null (0, null);
        };

        return #Ok({
          network = NETWORK_NAME;
          account;
          token = ?tokenMaster;
          amount = ?format_units(amountRaw, Nat8.toNat(decimals));
          decimals = ?decimals;
          block_ref = null;
          pending = false;
          message = ?(
            switch (walletTextOpt) {
              case (?w) "TON v3 jetton/wallets (" # w # ")";
              case null "TON v3 jetton/wallets (no wallet yet => balance 0)";
            }
          );
        });
      };
      case null {};
    };

    let payload = switch (await ton_v2_get_json(
      "/getAddressBalance?address=" # percent_encode(account),
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (json_object_field(payload, "ok")) {
      case (?#Boolean(ok)) {
        if (not ok) {
          let errText = switch (json_object_field(payload, "error")) {
            case (?#String(s)) s;
            case (?v) JsonAst.show(v);
            case null "TON RPC returned ok=false";
          };
          return #Err(#Internal("TON RPC error: " # errText));
        };
      };
      case (_) {};
    };
    let nanotonsText = switch (json_object_field(payload, "result")) {
      case (?#String(s)) s;
      case (?#Number(n)) {
        if (n < 0) return #Err(#Internal("TON balance is negative"));
        Int.toText(n)
      };
      case (_) return #Err(#Internal("TON RPC missing result field"));
    };
    let nanotons = switch (nat_from_decimal_text(nanotonsText)) {
      case (?v) v;
      case null return #Err(#Internal("TON balance parse failed"));
    };

    #Ok({
      network = NETWORK_NAME;
      account;
      token = null;
      amount = ?format_units(nanotons, Nat8.toNat(TON_DECIMALS));
      decimals = ?TON_DECIMALS;
      block_ref = null;
      pending = false;
      message = ?"TON RPC getAddressBalance";
    })
  };

  public func discover_jetton_token(token_address : Text) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let master = switch (TonTx.parse_ton_address(token_address)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let canonical = TonTx.format_user_friendly_address(master, false, false);
    let decimals : Nat8 = switch (await fetch_jetton_decimals_from_v3(canonical, null)) {
      case (?d) d;
      case null 9;
    };
    let (symbol, name) = switch (await fetch_jetton_name_symbol_from_v3(canonical, null)) {
      case (#Ok(v)) v;
      case (#Err(_)) ("JETTON", "Jetton " # truncate_text(canonical, 24));
    };
    #Ok({
      network = NETWORK_NAME;
      symbol;
      name;
      token_address = canonical;
      decimals = Nat8.toNat(decimals);
    })
  };

  public func transfer_ton(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_ton_with_rpc(null, req)
  };

  public func transfer_ton_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) > 0) {
          return #Err(#InvalidInput("ton_transfer_ton does not accept token parameter"));
        };
      };
      case null {};
    };
    if (Text.size(Text.trim(req.to, #char ' ')) == 0) {
      return #Err(#InvalidInput("to is required"));
    };
    if (Text.size(Text.trim(req.amount, #char ' ')) == 0) {
      return #Err(#InvalidInput("amount is required"));
    };

    let managed = switch (await fetch_managed_ton_wallet()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    switch (req.from) {
      case (?fromTextRaw) {
        let fromTrimmed = Text.trim(fromTextRaw, #char ' ');
        if (Text.size(fromTrimmed) > 0) {
          let fromAddr = switch (TonTx.parse_ton_address(fromTrimmed)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          if (not same_ton_address(fromAddr, managed.address)) {
            return #Err(#InvalidInput("from does not match canister-managed TON wallet address"));
          };
        };
      };
      case null {};
    };

    let toAddr = switch (TonTx.parse_ton_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let amountNanotons = switch (parse_decimal_units(req.amount, Nat8.toNat(TON_DECIMALS))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountNanotons == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };

    let bodyOpt : ?TonTx.Cell = switch (req.memo) {
      case (?memoText) {
        let memoTrimmed = Text.trim(memoText, #char ' ');
        if (Text.size(memoTrimmed) == 0) {
          null
        } else {
          switch (TonTx.build_comment_body(memoTrimmed)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(cell)) ?cell;
          }
        }
      };
      case null null;
    };
    let bounce = switch (toAddr.bounceable) {
      case (?b) b;
      case null true;
    };
    let outMsg = switch (TonTx.build_internal_message(toAddr, amountNanotons, bounce, bodyOpt)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    await send_wallet_message(managed, outMsg, rpcOverride)
  };

  public func transfer_jetton(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_jetton_with_rpc(null, req)
  };

  public func transfer_jetton_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    let tokenMasterTextRaw = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) return #Err(#InvalidInput("token is required for jetton transfer"));
        trimmed
      };
      case null return #Err(#InvalidInput("token is required for jetton transfer"));
    };
    if (Text.size(Text.trim(req.to, #char ' ')) == 0) {
      return #Err(#InvalidInput("to is required"));
    };
    if (Text.size(Text.trim(req.amount, #char ' ')) == 0) {
      return #Err(#InvalidInput("amount is required"));
    };

    let managed = switch (await fetch_managed_ton_wallet()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (req.from) {
      case (?fromTextRaw) {
        let fromTrimmed = Text.trim(fromTextRaw, #char ' ');
        if (Text.size(fromTrimmed) > 0) {
          let fromAddr = switch (TonTx.parse_ton_address(fromTrimmed)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          if (not same_ton_address(fromAddr, managed.address)) {
            return #Err(#InvalidInput("from does not match canister-managed TON wallet address"));
          };
        };
      };
      case null {};
    };

    let toOwner = switch (TonTx.parse_ton_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let tokenMasterAddr = switch (TonTx.parse_ton_address(tokenMasterTextRaw)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let senderJettonWallet = switch (await fetch_jetton_wallet_for_owner(managed.address, tokenMasterAddr, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(?v)) v;
      case (#Ok(null)) {
        return #Err(#Internal("sender jetton wallet not found (fund token first so wallet is created)"));
      };
    };

    let tokenMasterFriendly = TonTx.format_user_friendly_address(tokenMasterAddr, false, false);
    let decimals = switch (await fetch_jetton_decimals_from_v3(tokenMasterFriendly, rpcOverride)) {
      case (?v) v;
      case null TON_DECIMALS;
    };
    let amountUnits = switch (parse_decimal_units(req.amount, Nat8.toNat(decimals))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountUnits == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };

    let body = switch (TonTx.build_jetton_transfer_body(
      amountUnits,
      toOwner,
      managed.address,
      TON_JETTON_FORWARD_AMOUNT_NANOTON,
      req.memo,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    var attachedTon : Nat = TON_JETTON_ATTACHED_NANOTON_DEFAULT;
    for ((k, v) in req.metadata.vals()) {
      let keyLower = Text.toLowercase(k);
      if (keyLower == "jetton_attached_ton" or keyLower == "ton_attached") {
        let parsed = switch (parse_decimal_units(v, Nat8.toNat(TON_DECIMALS))) {
          case (#Err(err)) return #Err(err);
          case (#Ok(n)) n;
        };
        attachedTon := parsed;
      };
    };
    if (attachedTon == 0) {
      return #Err(#InvalidInput("attached TON for jetton transfer must be > 0"));
    };

    let outMsg = switch (TonTx.build_internal_message(senderJettonWallet.address, attachedTon, true, ?body)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    await send_wallet_message(managed, outMsg, rpcOverride)
  };

  func send_wallet_message(
    managed : ManagedTonWallet,
    outMsg : TonTx.Cell,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<Types.TransferResponse> {
    let walletState = switch (await fetch_wallet_state(managed.address, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let nowSecs : Nat = Int.abs(Time.now()) / 1_000_000_000;
    let validUntil = Nat32.fromNat(nowSecs + TON_VALID_UNTIL_SECS_AHEAD);

    let signingBody = switch (TonTx.build_wallet_v4r2_signing_body(
      TonTx.TON_WALLET_V4R2_WALLET_ID,
      validUntil,
      walletState.seqno,
      TON_WALLET_MODE_DEFAULT,
      outMsg,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signingHash = TonTx.cell_hash(signingBody);
    let signature = switch (await sign_ton_hash(signingHash)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let body = switch (TonTx.build_wallet_v4r2_body_with_signature(signature, signingBody)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let stateInitOpt = if (walletState.active) null else ?managed.state_init;
    let extMessage = switch (TonTx.build_external_message(managed.address, body, stateInitOpt)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let bocB64 = switch (TonTx.cell_to_boc_base64(extMessage)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let sendRes = await ton_v2_post_json_boc("/sendBocReturnHash", bocB64, rpcOverride);
    switch (sendRes) {
      case (#Ok(payload)) {
        let txid = extract_send_boc_hash(payload);
        #Ok({
          network = NETWORK_NAME;
          accepted = true;
          tx_id = txid;
          message = switch (txid) {
            case (?h) "TON sendBocReturnHash accepted: " # h;
            case null "TON sendBocReturnHash accepted";
          };
        })
      };
      case (#Err(primaryErr)) {
        switch (await ton_v2_post_json_boc("/sendBoc", bocB64, rpcOverride)) {
          case (#Ok(_)) {
            #Ok({
              network = NETWORK_NAME;
              accepted = true;
              tx_id = null;
              message = "TON sendBoc accepted";
            })
          };
          case (#Err(fallbackErr)) {
            #Err(#Internal(
              "TON sendBocReturnHash failed: " # wallet_error_text(primaryErr) #
              "; sendBoc failed: " # wallet_error_text(fallbackErr)
            ))
          };
        }
      };
    }
  };

  func fetch_managed_ton_wallet() : async Error.WalletResult<ManagedTonWallet> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((pubkey, _key_name))) {
        if (pubkey.size() != 32) {
          return #Err(#Internal("unexpected ed25519 public key length for TON wallet: " # Nat.toText(pubkey.size())));
        };
        let code = switch (TonTx.wallet_v4r2_code_cell()) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let data = switch (TonTx.wallet_v4r2_data_cell(pubkey, TonTx.TON_WALLET_V4R2_WALLET_ID)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let stateInit = switch (TonTx.state_init_cell(code, data)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let addr = TonTx.contract_address_from_state_init(stateInit, TonTx.TON_WORKCHAIN_BASECHAIN);
        #Ok({
          address = addr;
          state_init = stateInit;
        })
      };
    }
  };

  func fetch_wallet_state(address : TonTx.TonAddress, rpcOverride : ?Text) : async Error.WalletResult<TonWalletState> {
    let addressText = TonTx.format_user_friendly_address(address, false, false);
    let payload = switch (await ton_v2_get_json_allow_rpc_not_ok(
      "/getWalletInformation?address=" # percent_encode(addressText),
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let ok = switch (json_object_field(payload, "ok")) {
      case (?#Boolean(b)) b;
      case (_) true;
    };
    if (not ok) {
      let msgLower = Text.toLowercase(
        switch (json_object_field(payload, "error")) {
          case (?#String(s)) s;
          case (?v) JsonAst.show(v);
          case null "unknown error";
        }
      );
      if (
        text_contains(msgLower, "not initialized") or
        text_contains(msgLower, "cannot get seqno") or
        text_contains(msgLower, "failed to execute get methods")
      ) {
        return #Ok({ seqno = 0; active = false });
      };
      return #Err(#Internal("TON getWalletInformation failed: " # truncate_text(JsonAst.show(payload), 300)));
    };
    let resultObj = switch (json_object_field(payload, "result")) {
      case (?v) v;
      case null payload;
    };
    let seqnoNat = switch (json_nat_field(resultObj, "seqno")) {
      case (?v) v;
      case null 0;
    };
    if (seqnoNat > 4_294_967_295) {
      return #Err(#Internal("TON seqno out of range"));
    };
    let accountState = switch (json_string_field(resultObj, "account_state")) {
      case (?s) s;
      case null switch (json_string_field(resultObj, "state")) {
        case (?s2) s2;
        case null "";
      };
    };
    let active = (accountState == "active") or (json_object_field(resultObj, "wallet") != null);
    #Ok({ seqno = Nat32.fromNat(seqnoNat); active })
  };

  func fetch_jetton_wallet_for_owner(
    owner : TonTx.TonAddress,
    jetton_master : TonTx.TonAddress,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<?JettonWalletInfo> {
    let ownerText = TonTx.format_user_friendly_address(owner, false, false);
    let masterText = TonTx.format_user_friendly_address(jetton_master, false, false);
    let payload = switch (await ton_v3_get_json(
      "/jetton/wallets?owner_address=" # percent_encode(ownerText) #
      "&jetton_address=" # percent_encode(masterText) #
      "&limit=1&offset=0",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let first = switch (first_jetton_wallet(payload)) {
      case (?v) v;
      case null return #Ok(null);
    };
    let addressText = switch (json_string_field(first, "address")) {
      case (?s) s;
      case null switch (json_string_field(first, "wallet_address")) {
        case (?s2) s2;
        case null return #Err(#Internal("TON v3 jetton wallet missing address"));
      };
    };
    let address = switch (TonTx.parse_ton_address(addressText)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let balance = switch (json_nat_field(first, "balance")) {
      case (?v) v;
      case null 0;
    };
    #Ok(?{
      address;
      address_text = addressText;
      balance;
    })
  };

  func sign_ton_hash(message_hash32 : [Nat8]) : async Error.WalletResult<[Nat8]> {
    if (message_hash32.size() != 32) {
      return #Err(#Internal("TON signing hash must be 32 bytes"));
    };
    let args : SignWithSchnorrArgs = {
      message = Blob.fromArray(message_hash32);
      derivation_path = [];
      key_id = {
        algorithm = #ed25519;
        name = AppConfig.default_schnorr_key_name();
      };
      aux = null;
    };
    try {
      let res = await Management.sign_with_schnorr(args);
      let sig = Blob.toArray(res.signature);
      if (sig.size() != 64) {
        return #Err(#Internal("unexpected TON ed25519 signature length: " # Nat.toText(sig.size())));
      };
      #Ok(sig)
    } catch e {
      #Err(#Internal("TON sign_with_schnorr failed: " # MoError.message(e)))
    }
  };

  func ton_v2_get_json_allow_rpc_not_ok(path : Text, rpcOverride : ?Text) : async Error.WalletResult<JsonAst.JSON> {
    let url = switch (ton_v2_url(path, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    await ton_http_get_json(url)
  };

  func ton_v2_post_json_boc(path : Text, bocB64 : Text, rpcOverride : ?Text) : async Error.WalletResult<JsonAst.JSON> {
    let url = switch (ton_v2_url(path, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let bodyText = "{\"boc\":\"" # json_escape(bocB64) # "\"}";
    let payload = switch (await ton_http_post_json(url, bodyText)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (json_object_field(payload, "ok")) {
      case (?#Boolean(ok)) {
        if (not ok) {
          let errText = switch (json_object_field(payload, "error")) {
            case (?#String(s)) s;
            case (?v) JsonAst.show(v);
            case null "TON RPC returned ok=false";
          };
          #Err(#Internal("TON RPC error: " # errText))
        } else {
          #Ok(payload)
        }
      };
      case (_) #Ok(payload);
    }
  };

  func ton_http_post_json(url : Text, bodyText : Text) : async Error.WalletResult<JsonAst.JSON> {
    let httpRes = switch (await Outcall.post_json(
      url,
      Text.encodeUtf8(bodyText),
      1024 * 1024 : Nat64,
      "ton rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("ton rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("ton rpc response is not utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("ton rpc parse response failed"));
    };
    #Ok(payload)
  };

  func extract_send_boc_hash(payload : JsonAst.JSON) : ?Text {
    switch (json_object_field(payload, "result")) {
      case (?#String(s)) ?s;
      case (?r) {
        switch (json_object_field(r, "hash")) {
          case (?#String(s2)) ?s2;
          case (_) {
            switch (json_object_field(payload, "hash")) {
              case (?#String(s3)) ?s3;
              case (_) null;
            }
          };
        }
      };
      case null {
        switch (json_object_field(payload, "hash")) {
          case (?#String(s4)) ?s4;
          case (_) null;
        }
      };
    }
  };

  func same_ton_address(a : TonTx.TonAddress, b : TonTx.TonAddress) : Bool {
    if (a.workchain != b.workchain) return false;
    if (a.hash.size() != b.hash.size()) return false;
    var i : Nat = 0;
    while (i < a.hash.size()) {
      if (a.hash[i] != b.hash[i]) return false;
      i += 1;
    };
    true
  };

  func parse_decimal_units(value : Text, decimals : Nat) : Error.WalletResult<Nat> {
    let t = Text.trim(value, #char ' ');
    if (Text.size(t) == 0) return #Err(#InvalidInput("amount is required"));
    if (Text.startsWith(t, #char '-')) return #Err(#InvalidInput("amount must be positive"));
    let chars = text_chars(t);
    var seenDot = false;
    var fracDigits : Nat = 0;
    var acc : Nat = 0;
    for (c in chars.vals()) {
      if (c == '.') {
        if (seenDot) return #Err(#InvalidInput("amount format is invalid"));
        seenDot := true;
      } else {
        if (c < '0' or c > '9') return #Err(#InvalidInput("amount must be decimal"));
        acc := (acc * 10) + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
        if (seenDot) {
          fracDigits += 1;
          if (fracDigits > decimals) return #Err(#InvalidInput("amount has too many decimal places"));
        };
      }
    };
    var pad : Nat = fracDigits;
    while (pad < decimals) {
      acc *= 10;
      pad += 1;
    };
    #Ok(acc)
  };

  func wallet_error_text(err : Error.WalletError) : Text {
    switch (err) {
      case (#Forbidden) "Forbidden";
      case (#Paused) "Paused";
      case (#InvalidInput(msg)) "InvalidInput(" # msg # ")";
      case (#Unimplemented(x)) "Unimplemented(" # x.network # "," # x.operation # ")";
      case (#Internal(msg)) "Internal(" # msg # ")";
    }
  };

  func text_contains(haystack : Text, needle : Text) : Bool {
    if (Text.size(needle) == 0) return true;
    let h = text_chars(haystack);
    let n = text_chars(needle);
    if (n.size() > h.size()) return false;
    var i : Nat = 0;
    while (i + n.size() <= h.size()) {
      var ok = true;
      var j : Nat = 0;
      while (j < n.size()) {
        if (h[i + j] != n[j]) {
          ok := false;
          j := n.size();
        } else {
          j += 1;
        };
      };
      if (ok) return true;
      i += 1;
    };
    false
  };

  func text_chars(t : Text) : [Char] {
    let buf = Buffer.Buffer<Char>(Text.size(t));
    for (c in t.chars()) { buf.add(c) };
    Buffer.toArray(buf)
  };

  func json_escape(value : Text) : Text {
    var out = "";
    for (c in value.chars()) {
      if (c == '\\') {
        out #= "\\\\";
      } else if (c == '\"') {
        out #= "\\\"";
      } else if (c == '\n') {
        out #= "\\n";
      } else if (c == '\r') {
        out #= "\\r";
      } else if (c == '\t') {
        out #= "\\t";
      } else {
        out #= Text.fromChar(c);
      };
    };
    out
  };

  func ton_v2_get_json(path : Text, rpcOverride : ?Text) : async Error.WalletResult<JsonAst.JSON> {
    let url = switch (ton_v2_url(path, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let payload = switch (await ton_http_get_json(url)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (json_object_field(payload, "ok")) {
      case (?#Boolean(ok)) {
        if (not ok) {
          let errText = switch (json_object_field(payload, "error")) {
            case (?#String(s)) s;
            case (?v) JsonAst.show(v);
            case null "TON RPC returned ok=false";
          };
          #Err(#Internal("TON RPC error: " # errText))
        } else {
          #Ok(payload)
        }
      };
      case (_) #Ok(payload);
    }
  };

  func ton_v3_get_json(path : Text, rpcOverride : ?Text) : async Error.WalletResult<JsonAst.JSON> {
    let url = switch (ton_v3_url(path, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    await ton_http_get_json(url)
  };

  func ton_http_get_json(url : Text) : async Error.WalletResult<JsonAst.JSON> {
    let httpRes = switch (await Outcall.get_json(url, 1024 * 1024 : Nat64, "ton rpc")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("ton rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("ton rpc response is not utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("ton rpc parse response failed"));
    };
    #Ok(payload)
  };

  func ton_v2_url(path : Text, rpcOverride : ?Text) : Error.WalletResult<Text> {
    let base = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("ton rpc url resolution failed: " # msg));
    };
    #Ok(join_url(base, path))
  };

  func ton_v3_url(path : Text, rpcOverride : ?Text) : Error.WalletResult<Text> {
    let baseV2 = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("ton rpc url resolution failed: " # msg));
    };
    let baseV3 = switch (Text.stripEnd(baseV2, #text "/api/v2")) {
      case (?prefix) prefix # "/api/v3";
      case null switch (Text.stripEnd(baseV2, #text "/v2")) {
        case (?prefix2) prefix2 # "/v3";
        case null trim_trailing_slash(baseV2) # "/api/v3";
      };
    };
    #Ok(join_url(baseV3, path))
  };

  func join_url(base : Text, path : Text) : Text {
    trim_trailing_slash(base) # path
  };

  func trim_trailing_slash(t : Text) : Text {
    switch (Text.stripEnd(t, #text "/")) {
      case (?v) v;
      case null t;
    }
  };

  func first_jetton_wallet(payload : JsonAst.JSON) : ?JsonAst.JSON {
    let arrOpt = switch (json_object_field(payload, "jetton_wallets")) {
      case (?#Array(a)) ?a;
      case (_) {
        switch (json_object_field(payload, "result")) {
          case (?#Array(a2)) ?a2;
          case (_) null;
        }
      }
    };
    switch (arrOpt) {
      case (?arr) {
        if (arr.size() == 0) null else ?arr[0]
      };
      case null null;
    }
  };

  func fetch_jetton_decimals_from_v3(tokenMaster : Text, rpcOverride : ?Text) : async ?Nat8 {
    let payload = switch (await ton_v3_get_json("/jetton/masters/" # percent_encode(tokenMaster), rpcOverride)) {
      case (#Err(_)) return null;
      case (#Ok(v)) v;
    };
    let candidates : [?JsonAst.JSON] = [
      switch (json_object_field(payload, "metadata")) {
        case (?m) json_object_field(m, "decimals");
        case null null;
      },
      switch (json_object_field(payload, "jetton_content")) {
        case (?jc) {
          switch (json_object_field(jc, "data")) {
            case (?d) json_object_field(d, "decimals");
            case null null;
          }
        };
        case null null;
      },
      json_object_field(payload, "decimals"),
    ];
    for (c in candidates.vals()) {
      switch (c) {
        case (?v) {
          switch (json_u8(v)) {
            case (?n) return ?n;
            case null {};
          }
        };
        case null {};
      }
    };
    null
  };

  func fetch_jetton_name_symbol_from_v3(tokenMaster : Text, rpcOverride : ?Text) : async Error.WalletResult<(Text, Text)> {
    let payload = switch (await ton_v3_get_json("/jetton/masters/" # percent_encode(tokenMaster), rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let meta = switch (json_object_field(payload, "metadata")) {
      case (?m) m;
      case null {
        switch (json_object_field(payload, "jetton_content")) {
          case (?jc) {
            switch (json_object_field(jc, "data")) {
              case (?d) d;
              case null return #Err(#Internal("TON jetton metadata missing"));
            }
          };
          case null return #Err(#Internal("TON jetton metadata missing"));
        }
      };
    };

    let symbol = switch (json_string_field(meta, "symbol")) {
      case (?s) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) return #Err(#Internal("TON jetton metadata missing symbol"));
        t
      };
      case null return #Err(#Internal("TON jetton metadata missing symbol"));
    };
    let name = switch (json_string_field(meta, "name")) {
      case (?s) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) symbol else t
      };
      case null symbol;
    };
    #Ok((symbol, name))
  };

  func percent_encode(t : Text) : Text {
    var out = "";
    let bytes = Blob.toArray(Text.encodeUtf8(t));
    for (b in bytes.vals()) {
      if (
        (b >= 48 and b <= 57) or
        (b >= 65 and b <= 90) or
        (b >= 97 and b <= 122) or
        b == 45 or b == 46 or b == 95 or b == 126
      ) {
        out #= Text.fromChar(Char.fromNat32(Nat32.fromNat(Nat8.toNat(b))));
      } else {
        out #= "%" # hex_upper_digit(Nat8.toNat(b / 16)) # hex_upper_digit(Nat8.toNat(b % 16));
      };
    };
    out
  };

  func hex_upper_digit(v : Nat) : Text {
    if (v < 10) {
      Text.fromChar(Char.fromNat32(Nat32.fromNat(48 + v)))
    } else {
      Text.fromChar(Char.fromNat32(Nat32.fromNat(65 + (v - 10))))
    }
  };

  func json_object_field(value : JsonAst.JSON, key : Text) : ?JsonAst.JSON {
    switch (value) {
      case (#Object(fields)) {
        for ((k, v) in fields.vals()) {
          if (k == key) return ?v;
        };
        null
      };
      case (_) null;
    }
  };

  func json_string_field(value : JsonAst.JSON, key : Text) : ?Text {
    switch (json_object_field(value, key)) {
      case (?#String(s)) ?s;
      case (_) null;
    }
  };

  func json_nat_field(value : JsonAst.JSON, key : Text) : ?Nat {
    switch (json_object_field(value, key)) {
      case (?#Number(n)) {
        if (n < 0) null else ?Int.abs(n)
      };
      case (?#String(s)) nat_from_decimal_text(s);
      case (_) null;
    }
  };

  func json_u8(value : JsonAst.JSON) : ?Nat8 {
    switch (value) {
      case (#Number(n)) {
        if (n < 0 or n > 255) null else ?Nat8.fromNat(Int.abs(n))
      };
      case (#String(s)) {
        switch (nat_from_decimal_text(s)) {
          case (?v) { if (v > 255) null else ?Nat8.fromNat(v) };
          case null null;
        }
      };
      case (_) null;
    }
  };

  func nat_from_decimal_text(input : Text) : ?Nat {
    let t = Text.trim(input, #char ' ');
    if (Text.size(t) == 0) return null;
    var acc : Nat = 0;
    for (c in t.chars()) {
      if (c < '0' or c > '9') return null;
      acc := (acc * 10) + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
    };
    ?acc
  };

  func format_units(amount : Nat, decimals : Nat) : Text {
    if (decimals == 0) return Nat.toText(amount);
    let base = pow10(decimals);
    let whole = amount / base;
    let frac = amount % base;
    if (frac == 0) return Nat.toText(whole);
    let fracRaw = Nat.toText(frac);
    let zerosNeeded = if (Text.size(fracRaw) >= decimals) 0 else decimals - Text.size(fracRaw);
    let fracPadded = repeat_text("0", zerosNeeded) # fracRaw;
    Nat.toText(whole) # "." # trim_trailing_zeros(fracPadded)
  };

  func pow10(n : Nat) : Nat {
    var out : Nat = 1;
    var i : Nat = 0;
    while (i < n) { out *= 10; i += 1 };
    out
  };

  func repeat_text(piece : Text, n : Nat) : Text {
    var out = "";
    var i : Nat = 0;
    while (i < n) { out #= piece; i += 1 };
    out
  };

  func trim_trailing_zeros(s : Text) : Text {
    let chars = Buffer.Buffer<Char>(Text.size(s));
    for (c in s.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    var end = arr.size();
    while (end > 0 and arr[end - 1] == '0') { end -= 1 };
    if (end == 0) return "0";
    var out = "";
    var i : Nat = 0;
    while (i < end) { out #= Text.fromChar(arr[i]); i += 1 };
    out
  };

  func truncate_text(t : Text, maxChars : Nat) : Text {
    if (Text.size(t) <= maxChars) return t;
    var out = "";
    var i : Nat = 0;
    for (c in t.chars()) {
      if (i >= maxChars) return out;
      out #= Text.fromChar(c);
      i += 1;
    };
    out
  };
}

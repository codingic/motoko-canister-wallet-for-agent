import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Blob "mo:base/Blob";
import MoError "mo:base/Error";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Addressing "./addressing";
import AppConfig "./config/app_config";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import Sha256 "./sha256";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.NEAR_MAINNET;
  let NEAR_DECIMALS : Nat8 = 24;
  let NEAR_GAS_FT_TRANSFER : Nat = 50_000_000_000_000; // 50 Tgas
  let NEAR_DEPOSIT_ONE_YOCTO : Nat = 1;

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

  type NearManagedIdentity = {
    account_id : Text;
    near_public_key : Text;
    public_key32 : [Nat8];
  };

  type NearAction = {
    #Transfer : { deposit : Nat };
    #FunctionCall : {
      method_name : Text;
      args : [Nat8];
      gas : Nat;
      deposit : Nat;
    };
  };

  let Management : actor {
    sign_with_schnorr : shared (SignWithSchnorrArgs) -> async SignWithSchnorrResult;
  } = actor "aaaaa-aa";

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((pubkey, key_name))) {
        if (pubkey.size() != 32) {
          return #Err(
            #Internal(
              "unexpected ed25519 public key length for NEAR address: " #
              Nat.toText(pubkey.size())
            )
          );
        };

        let implicit_account = Addressing.hex_encode(pubkey);
        let near_pubkey = "ed25519:" # Addressing.base58_encode(pubkey);

        #Ok({
          network = NETWORK_NAME;
          address = implicit_account;
          public_key_hex = Addressing.hex_encode(pubkey);
          key_name;
          message = ?("NEAR implicit account (public key " # near_pubkey # ")");
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
    let account = Text.trim(req.account, #char ' ');
    if (Text.size(account) == 0) {
      return #Err(#InvalidInput("account is required"));
    };
    let tokenOpt : ?Text = switch (req.token) {
      case (?token) {
        let t = Text.trim(token, #char ' ');
        if (Text.size(t) == 0) null else ?t;
      };
      case null null;
    };

    switch (tokenOpt) {
      case (?contractId) {
        let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
          case (#ok(url)) url;
          case (#err(msg)) return #Err(#Internal("near rpc url resolution failed: " # msg));
        };
        let argsJson = "{\"account_id\":\"" # json_escape(account) # "\"}";
        let balanceBytes = switch (await near_call_function_bytes(rpcUrl, contractId, "ft_balance_of", argsJson)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(bytes)) bytes;
        };
        let balanceTextJson = switch (Text.decodeUtf8(Blob.fromArray(balanceBytes))) {
          case (?t) t;
          case null return #Err(#Internal("NEAR ft_balance_of returned non-utf8 bytes"));
        };
        let balanceValue = switch (JsonAst.parse(Text.trim(balanceTextJson, #char ' '))) {
          case (?v) v;
          case null return #Err(#Internal("NEAR ft_balance_of json parse failed"));
        };
        let amountRaw = switch (balanceValue) {
          case (#String(s)) {
            switch (nat_from_decimal_text(s)) {
              case (?v) v;
              case null return #Err(#Internal("NEAR ft_balance_of amount parse failed"));
            }
          };
          case (_) return #Err(#Internal("NEAR ft_balance_of returned unexpected payload"));
        };
        let decimals : Nat8 = switch (await fetch_nep141_decimals(rpcUrl, contractId)) {
          case (?d) d;
          case null 24;
        };
        return #Ok({
          network = NETWORK_NAME;
          account;
          token = ?contractId;
          amount = ?format_units(amountRaw, Nat8.toNat(decimals));
          decimals = ?decimals;
          block_ref = null;
          pending = false;
          message = ?"NEAR RPC query(call_function ft_balance_of)";
        });
      };
      case null {};
    };

    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("near rpc url resolution failed: " # msg));
    };

    let bodyText =
      "{\"jsonrpc\":\"2.0\",\"id\":\"wallet\",\"method\":\"query\",\"params\":{" #
      "\"request_type\":\"view_account\",\"finality\":\"final\",\"account_id\":\"" # json_escape(account) # "\"" #
      "}}";
    let httpRes = switch (await Outcall.post_json(
      rpcUrl,
      Text.encodeUtf8(bodyText),
      near_rpc_max_response_bytes_for_query_request_type("view_account"),
      "near rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };

    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 300);
        case null "<non-utf8>";
      };
      return #Err(#Internal("near rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };

    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("parse near rpc response failed: non-utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse near rpc response failed"));
    };

    switch (json_object_field(payload, "error")) {
      case (?errValue) {
        let errText = JsonAst.show(errValue);
        if (text_contains(errText, "UNKNOWN_ACCOUNT") or text_contains(errText, "does not exist while viewing")) {
          return #Ok({
            network = NETWORK_NAME;
            account;
            token = null;
            amount = ?"0";
            decimals = ?24;
            block_ref = null;
            pending = false;
            message = ?"NEAR implicit account not initialized on-chain yet; treating balance as 0";
          });
        };
        return #Err(#Internal("NEAR RPC error: " # truncate_text(errText, 300)));
      };
      case null {};
    };

    let resultValue = switch (json_object_field(payload, "result")) {
      case (?v) v;
      case null return #Err(#Internal("NEAR RPC missing result"));
    };
    let amountText = switch (json_object_field(resultValue, "amount")) {
      case (?#String(s)) s;
      case (_) return #Err(#Internal("NEAR view_account missing amount"));
    };
    let yocto = switch (nat_from_decimal_text(amountText)) {
      case (?v) v;
      case null return #Err(#Internal("NEAR amount parse failed"));
    };

    #Ok({
      network = NETWORK_NAME;
      account;
      token = null;
      amount = ?format_units(yocto, 24);
      decimals = ?24;
      block_ref = null;
      pending = false;
      message = ?"NEAR RPC query(view_account)";
    })
  };

  public func transfer(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_with_rpc(null, req)
  };

  public func transfer_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    if (Text.size(Text.trim(req.to, #char ' ')) == 0) {
      return #Err(#InvalidInput("to is required"));
    };
    if (Text.size(Text.trim(req.amount, #char ' ')) == 0) {
      return #Err(#InvalidInput("amount is required"));
    };

    let managed = switch (await fetch_managed_near_identity()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (req.from) {
      case (?fromText) {
        let fromTrimmed = Text.trim(fromText, #char ' ');
        if (Text.size(fromTrimmed) > 0 and fromTrimmed != managed.account_id) {
          return #Err(#InvalidInput("from does not match canister-managed NEAR account"));
        };
      };
      case null {};
    };

    let tokenOpt : ?Text = switch (req.token) {
      case (?token) {
        let t = Text.trim(token, #char ' ');
        if (Text.size(t) == 0) null else ?t;
      };
      case null null;
    };
    let access = switch (await near_rpc_call_result(
      "query",
      "{" #
      "\"request_type\":\"view_access_key\"," #
      "\"finality\":\"final\"," #
      "\"account_id\":\"" # json_escape(managed.account_id) # "\"," #
      "\"public_key\":\"" # json_escape(managed.near_public_key) # "\"" #
      "}",
      rpcOverride,
    )) {
      case (#Err(#Internal(msg))) {
        if (is_near_unknown_account_error_text(msg)) {
          return #Err(#InvalidInput(
            "managed NEAR account is not initialized on-chain yet; fund the implicit account first"
          ));
        };
        return #Err(#Internal(msg));
      };
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let nonce0 = switch (json_nat_field(access, "nonce")) {
      case (?n) n;
      case null return #Err(#Internal("NEAR view_access_key missing nonce"));
    };
    let nonce = nonce0 + 1;
    let blockHashB58 = switch (json_string_field(access, "block_hash")) {
      case (?s) s;
      case null return #Err(#Internal("NEAR view_access_key missing block_hash"));
    };
    let blockHash = switch (base58_decode(blockHashB58)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (blockHash.size() != 32) {
      return #Err(#Internal("NEAR block_hash must decode to 32 bytes"));
    };

    let toAccount = Text.trim(req.to, #char ' ');
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("near rpc url resolution failed: " # msg));
    };

    let action : NearAction = switch (tokenOpt) {
      case null {
        let amountNat = switch (parse_decimal_units(req.amount, Nat8.toNat(NEAR_DECIMALS))) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        if (amountNat == 0) return #Err(#InvalidInput("amount must be > 0"));
        let deposit = switch (nat_to_u128(amountNat)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        #Transfer({ deposit })
      };
      case (?contractId) {
        let decimals = switch (await fetch_nep141_decimals(rpcUrl, contractId)) {
          case (?d) d;
          case null NEAR_DECIMALS;
        };
        let amountNat = switch (parse_decimal_units(req.amount, Nat8.toNat(decimals))) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        if (amountNat == 0) return #Err(#InvalidInput("amount must be > 0"));
        let amountU128 = switch (nat_to_u128(amountNat)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let memoField = switch (req.memo) {
          case (?m0) {
            let m = Text.trim(m0, #char ' ');
            if (Text.size(m) == 0) {
              ""
            } else {
              ",\"memo\":\"" # json_escape(m) # "\""
            }
          };
          case null "";
        };
        let argsJson =
          "{" #
          "\"receiver_id\":\"" # json_escape(toAccount) # "\"," #
          "\"amount\":\"" # Nat.toText(amountU128) # "\"" #
          memoField #
          "}";
        #FunctionCall({
          method_name = "ft_transfer";
          args = Blob.toArray(Text.encodeUtf8(argsJson));
          gas = NEAR_GAS_FT_TRANSFER;
          deposit = NEAR_DEPOSIT_ONE_YOCTO;
        })
      };
    };

    let receiverId = switch (tokenOpt) {
      case (?contractId) contractId;
      case null toAccount;
    };
    let txBytes = switch (
      encode_near_transaction_borsh(
        managed.account_id,
        managed.public_key32,
        nonce,
        receiverId,
        blockHash,
        [action],
      )
    ) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let txHash = Blob.toArray(Sha256.fromArray(#sha256, txBytes));
    let signature = switch (await sign_near_tx_hash(txHash)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signedTxBytes = encode_near_signed_transaction_borsh(txBytes, signature);
    let signedB64 = base64_encode(signedTxBytes);
    let res = switch (await near_rpc_call_result("broadcast_tx_commit", "[\"" # json_escape(signedB64) # "\"]", rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let txId = switch (json_object_field(res, "transaction")) {
      case (?txObj) {
        switch (json_string_field(txObj, "hash")) {
          case (?s) ?s;
          case null {
            switch (json_object_field(res, "transaction_outcome")) {
              case (?outcomeObj) json_string_field(outcomeObj, "id");
              case null null;
            }
          }
        }
      };
      case null {
        switch (json_object_field(res, "transaction_outcome")) {
          case (?outcomeObj) json_string_field(outcomeObj, "id");
          case null null;
        }
      };
    };
    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = txId;
      message = switch (txId) {
        case (?h) "NEAR broadcast_tx_commit accepted: " # h;
        case null "NEAR broadcast_tx_commit accepted";
      };
    })
  };

  public func discover_nep141_token(contract_id : Text) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let contractId = Text.toLowercase(Text.trim(contract_id, #char ' '));
    if (Text.size(contractId) == 0) {
      return #Err(#InvalidInput("token contract id is required"));
    };
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, null)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("near rpc url resolution failed: " # msg));
    };
    let metaBytes = switch (await near_call_function_bytes(rpcUrl, contractId, "ft_metadata", "{}")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let metaText = switch (Text.decodeUtf8(Blob.fromArray(metaBytes))) {
      case (?t) t;
      case null return #Err(#Internal("NEAR ft_metadata returned non-utf8 bytes"));
    };
    let metaJson = switch (JsonAst.parse(Text.trim(metaText, #char ' '))) {
      case (?v) v;
      case null return #Err(#Internal("NEAR ft_metadata json parse failed"));
    };

    let decimals : Nat8 = switch (json_object_field(metaJson, "decimals")) {
      case (?#Number(n)) {
        if (n < 0 or n > 255) return #Err(#Internal("NEAR ft_metadata missing decimals"));
        Nat8.fromNat(Int.abs(n))
      };
      case (?#String(s)) {
        switch (nat_from_decimal_text(s)) {
          case (?v) {
            if (v > 255) return #Err(#Internal("NEAR ft_metadata missing decimals"));
            Nat8.fromNat(v)
          };
          case null return #Err(#Internal("NEAR ft_metadata missing decimals"));
        }
      };
      case (_) return #Err(#Internal("NEAR ft_metadata missing decimals"));
    };

    let symbol = switch (json_object_field(metaJson, "symbol")) {
      case (?#String(s)) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) return #Err(#Internal("NEAR ft_metadata missing symbol"));
        t
      };
      case (_) return #Err(#Internal("NEAR ft_metadata missing symbol"));
    };
    let name = switch (json_object_field(metaJson, "name")) {
      case (?#String(s)) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) symbol else t
      };
      case (_) symbol;
    };

    #Ok({
      network = NETWORK_NAME;
      symbol;
      name;
      token_address = contractId;
      decimals = Nat8.toNat(decimals);
    })
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

  func json_nat_value(value : JsonAst.JSON) : ?Nat {
    switch (value) {
      case (#Number(n)) {
        if (n < 0) null else ?Int.abs(n)
      };
      case (#String(s)) nat_from_decimal_text(s);
      case (_) null;
    }
  };

  func json_nat_field(value : JsonAst.JSON, key : Text) : ?Nat {
    switch (json_object_field(value, key)) {
      case (?v) json_nat_value(v);
      case null null;
    }
  };

  func is_near_unknown_account_error_text(msg : Text) : Bool {
    text_contains(msg, "UNKNOWN_ACCOUNT") or text_contains(msg, "does not exist while viewing")
  };

  func near_rpc_call_result(
    method : Text,
    paramsJson : Text,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let base = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("near rpc url resolution failed: " # msg));
    };
    let bodyText =
      "{\"jsonrpc\":\"2.0\",\"id\":\"near-wallet\",\"method\":\"" # json_escape(method) # "\",\"params\":" # paramsJson # "}";
    let httpRes = switch (await Outcall.post_json(
      base,
      Text.encodeUtf8(bodyText),
      near_rpc_max_response_bytes_for_method(method),
      "near rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 300);
        case null "<non-utf8>";
      };
      return #Err(#Internal("near rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("parse near rpc response failed: non-utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse near rpc response failed"));
    };
    switch (json_object_field(payload, "error")) {
      case (?errValue) return #Err(#Internal("NEAR RPC error: " # truncate_text(JsonAst.show(errValue), 300)));
      case null {};
    };
    switch (json_object_field(payload, "result")) {
      case (?v) #Ok(v);
      case null #Err(#Internal("NEAR RPC missing result"));
    }
  };

  func fetch_managed_near_identity() : async Error.WalletResult<NearManagedIdentity> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((pubkey, _))) {
        if (pubkey.size() != 32) {
          return #Err(
            #Internal(
              "unexpected ed25519 public key length for NEAR signer: " # Nat.toText(pubkey.size())
            )
          );
        };
        #Ok({
          account_id = Addressing.hex_encode(pubkey);
          near_public_key = "ed25519:" # Addressing.base58_encode(pubkey);
          public_key32 = pubkey;
        })
      };
    }
  };

  func sign_near_tx_hash(hash32 : [Nat8]) : async Error.WalletResult<[Nat8]> {
    if (hash32.size() != 32) return #Err(#Internal("NEAR tx hash must be 32 bytes"));
    let args : SignWithSchnorrArgs = {
      message = Blob.fromArray(hash32);
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
        return #Err(#Internal("unexpected NEAR signature length: " # Nat.toText(sig.size())));
      };
      #Ok(sig)
    } catch e {
      #Err(#Internal("sign_with_schnorr failed: " # MoError.message(e)))
    }
  };

  func encode_near_signed_transaction_borsh(txBytes : [Nat8], signature64 : [Nat8]) : [Nat8] {
    let out = Buffer.Buffer<Nat8>(txBytes.size() + 65);
    for (b in txBytes.vals()) { out.add(b) };
    near_signature_borsh(out, signature64);
    Buffer.toArray(out)
  };

  func encode_near_transaction_borsh(
    signerId : Text,
    publicKey32 : [Nat8],
    nonce : Nat,
    receiverId : Text,
    blockHash32 : [Nat8],
    actions : [NearAction],
  ) : Error.WalletResult<[Nat8]> {
    if (publicKey32.size() != 32) return #Err(#Internal("NEAR signer public key must be 32 bytes"));
    if (blockHash32.size() != 32) return #Err(#Internal("NEAR block_hash must be 32 bytes"));
    let nonceU64 = switch (nat_to_u64(nonce)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let out = Buffer.Buffer<Nat8>(256);
    switch (borsh_string(out, signerId)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    near_public_key_borsh(out, publicKey32);
    append_u64_le(out, nonceU64);
    switch (borsh_string(out, receiverId)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    append_bytes(out, blockHash32);
    switch (borsh_u32(out, actions.size())) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    for (action in actions.vals()) {
      switch (encode_near_action_borsh(out, action)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(())) {};
      };
    };
    #Ok(Buffer.toArray(out))
  };

  func encode_near_action_borsh(out : Buffer.Buffer<Nat8>, action : NearAction) : Error.WalletResult<()> {
    switch (action) {
      case (#Transfer({ deposit })) {
        let depositU128 = switch (nat_to_u128(deposit)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        out.add(3); // Action::Transfer
        append_u128_le(out, depositU128);
        #Ok(())
      };
      case (#FunctionCall({ method_name; args; gas; deposit })) {
        let gasU64 = switch (nat_to_u64(gas)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let depositU128 = switch (nat_to_u128(deposit)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        out.add(2); // Action::FunctionCall
        switch (borsh_string(out, method_name)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(())) {};
        };
        switch (borsh_bytes(out, args)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(())) {};
        };
        append_u64_le(out, gasU64);
        append_u128_le(out, depositU128);
        #Ok(())
      };
    }
  };

  func near_public_key_borsh(out : Buffer.Buffer<Nat8>, pk32 : [Nat8]) {
    out.add(0); // ED25519
    append_bytes(out, pk32);
  };

  func near_signature_borsh(out : Buffer.Buffer<Nat8>, sig64 : [Nat8]) {
    out.add(0); // ED25519
    append_bytes(out, sig64);
  };

  func borsh_string(out : Buffer.Buffer<Nat8>, value : Text) : Error.WalletResult<()> {
    borsh_bytes(out, Blob.toArray(Text.encodeUtf8(value)))
  };

  func borsh_bytes(out : Buffer.Buffer<Nat8>, bytes : [Nat8]) : Error.WalletResult<()> {
    switch (borsh_u32(out, bytes.size())) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    append_bytes(out, bytes);
    #Ok(())
  };

  func borsh_u32(out : Buffer.Buffer<Nat8>, value : Nat) : Error.WalletResult<()> {
    if (value > 4_294_967_295) {
      return #Err(#Internal("borsh length exceeds u32"));
    };
    append_u32_le(out, value);
    #Ok(())
  };

  func append_bytes(out : Buffer.Buffer<Nat8>, bytes : [Nat8]) {
    for (b in bytes.vals()) { out.add(b) };
  };

  func append_u32_le(out : Buffer.Buffer<Nat8>, n : Nat) {
    var v = n;
    var i : Nat = 0;
    while (i < 4) {
      out.add(Nat8.fromNat(v % 256));
      v /= 256;
      i += 1;
    };
  };

  func append_u64_le(out : Buffer.Buffer<Nat8>, n : Nat) {
    var v = n;
    var i : Nat = 0;
    while (i < 8) {
      out.add(Nat8.fromNat(v % 256));
      v /= 256;
      i += 1;
    };
  };

  func append_u128_le(out : Buffer.Buffer<Nat8>, n : Nat) {
    var v = n;
    var i : Nat = 0;
    while (i < 16) {
      out.add(Nat8.fromNat(v % 256));
      v /= 256;
      i += 1;
    };
  };

  func nat_to_u64(n : Nat) : Error.WalletResult<Nat> {
    if (n > 18_446_744_073_709_551_615) {
      #Err(#InvalidInput("amount is too large"))
    } else {
      #Ok(n)
    }
  };

  func nat_to_u128(n : Nat) : Error.WalletResult<Nat> {
    let maxPlusOne : Nat = 0x1_000000000000000000000000000000000;
    if (n >= maxPlusOne) {
      #Err(#InvalidInput("amount is too large"))
    } else {
      #Ok(n)
    }
  };

  func parse_decimal_units(value : Text, decimals : Nat) : Error.WalletResult<Nat> {
    let t = Text.trim(value, #char ' ');
    if (Text.size(t) == 0) return #Err(#InvalidInput("amount is required"));
    if (Text.startsWith(t, #char '-')) return #Err(#InvalidInput("amount must be positive"));
    var seenDot = false;
    var fracDigits : Nat = 0;
    var acc : Nat = 0;
    for (c in t.chars()) {
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
      };
    };
    var pad = fracDigits;
    while (pad < decimals) {
      acc *= 10;
      pad += 1;
    };
    #Ok(acc)
  };

  func base58_decode(input0 : Text) : Error.WalletResult<[Nat8]> {
    let input = Text.trim(input0, #char ' ');
    if (Text.size(input) == 0) return #Err(#InvalidInput("base58 string is required"));
    let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    var zeros : Nat = 0;
    label z for (c in input.chars()) {
      if (c == '1') {
        zeros += 1;
      } else {
        break z;
      };
    };
    var acc : Nat = 0;
    for (c in input.chars()) {
      let digit = switch (base58_index(alphabet, c)) {
        case (?d) d;
        case null return #Err(#InvalidInput("invalid base58 character"));
      };
      acc := (acc * 58) + digit;
    };
    let out = nat_to_bytes_be(acc);
    if (zeros == 0) return #Ok(out);
    #Ok(Array.append(Array.tabulate<Nat8>(zeros, func(_ : Nat) : Nat8 = 0), out))
  };

  func base58_index(alphabet : Text, c : Char) : ?Nat {
    var i : Nat = 0;
    for (x in alphabet.chars()) {
      if (x == c) return ?i;
      i += 1;
    };
    null
  };

  func nat_to_bytes_be(n0 : Nat) : [Nat8] {
    if (n0 == 0) return [];
    let out = Buffer.Buffer<Nat8>(32);
    var n = n0;
    while (n > 0) {
      out.add(Nat8.fromNat(n % 256));
      n /= 256;
    };
    Array.reverse(Buffer.toArray(out))
  };

  func near_rpc_max_response_bytes_for_method(method : Text) : Nat64 {
    switch (method) {
      case ("status") 16 * 1024 : Nat64;
      case ("query") 64 * 1024 : Nat64;
      case ("broadcast_tx_commit") 256 * 1024 : Nat64;
      case (_) 128 * 1024 : Nat64;
    }
  };

  func near_rpc_max_response_bytes_for_query_request_type(requestType : Text) : Nat64 {
    switch (requestType) {
      case ("view_account") 16 * 1024 : Nat64;
      case ("view_access_key") 32 * 1024 : Nat64;
      case ("call_function") 64 * 1024 : Nat64;
      case (_) 64 * 1024 : Nat64;
    }
  };

  func near_call_function_bytes(
    rpcUrl : Text,
    accountId : Text,
    methodName : Text,
    argsJson : Text,
  ) : async Error.WalletResult<[Nat8]> {
    let argsB64 = base64_encode(Blob.toArray(Text.encodeUtf8(argsJson)));
    let bodyText =
      "{\"jsonrpc\":\"2.0\",\"id\":\"near-wallet\",\"method\":\"query\",\"params\":{" #
      "\"request_type\":\"call_function\",\"finality\":\"final\"," #
      "\"account_id\":\"" # json_escape(accountId) # "\"," #
      "\"method_name\":\"" # json_escape(methodName) # "\"," #
      "\"args_base64\":\"" # json_escape(argsB64) # "\"" #
      "}}";
    let httpRes = switch (await Outcall.post_json(
      rpcUrl,
      Text.encodeUtf8(bodyText),
      near_rpc_max_response_bytes_for_query_request_type("call_function"),
      "near rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 300);
        case null "<non-utf8>";
      };
      return #Err(#Internal("near rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("parse near rpc response failed: non-utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse near rpc response failed"));
    };
    switch (json_object_field(payload, "error")) {
      case (?errValue) return #Err(#Internal("NEAR RPC error: " # truncate_text(JsonAst.show(errValue), 300)));
      case null {};
    };
    let resultValue = switch (json_object_field(payload, "result")) {
      case (?v) v;
      case null return #Err(#Internal("NEAR RPC missing result"));
    };
    let bytesArray = switch (json_object_field(resultValue, "result")) {
      case (?#Array(items)) items;
      case (_) return #Err(#Internal("NEAR call_function missing result bytes"));
    };
    let out = Buffer.Buffer<Nat8>(bytesArray.size());
    for (item in bytesArray.vals()) {
      switch (item) {
        case (#Number(n)) {
          if (n < 0 or n > 255) {
            return #Err(#Internal("NEAR call_function result byte out of range"));
          };
          out.add(Nat8.fromNat(Int.abs(n)));
        };
        case (_) return #Err(#Internal("NEAR call_function result byte is not number"));
      };
    };
    #Ok(Buffer.toArray(out))
  };

  func fetch_nep141_decimals(rpcUrl : Text, contractId : Text) : async ?Nat8 {
    let metaBytes = switch (await near_call_function_bytes(rpcUrl, contractId, "ft_metadata", "{}")) {
      case (#Err(_)) return null;
      case (#Ok(bytes)) bytes;
    };
    let metaText = switch (Text.decodeUtf8(Blob.fromArray(metaBytes))) {
      case (?t) t;
      case null return null;
    };
    let metaJson = switch (JsonAst.parse(Text.trim(metaText, #char ' '))) {
      case (?v) v;
      case null return null;
    };
    switch (json_object_field(metaJson, "decimals")) {
      case (?#Number(n)) {
        if (n < 0 or n > 255) null else ?Nat8.fromNat(Int.abs(n))
      };
      case (?#String(s)) {
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
    while (i < n) {
      out *= 10;
      i += 1;
    };
    out
  };

  func repeat_text(piece : Text, n : Nat) : Text {
    var out = "";
    var i : Nat = 0;
    while (i < n) {
      out #= piece;
      i += 1;
    };
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
    while (i < end) {
      out #= Text.fromChar(arr[i]);
      i += 1;
    };
    out
  };

  func text_contains(haystack : Text, needle : Text) : Bool {
    if (Text.size(needle) == 0) return true;
    let h = Blob.toArray(Text.encodeUtf8(haystack));
    let n = Blob.toArray(Text.encodeUtf8(needle));
    if (n.size() == 0) return true;
    if (h.size() < n.size()) return false;
    var i : Nat = 0;
    while (i + n.size() <= h.size()) {
      var j : Nat = 0;
      var ok = true;
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

  func base64_encode(bytes : [Nat8]) : Text {
    let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let out = Buffer.Buffer<Text>(((Array.size(bytes) + 2) / 3) * 4);
    var i : Nat = 0;
    while (i < Array.size(bytes)) {
      let b0 = Nat8.toNat(bytes[i]);
      let has1 = i + 1 < Array.size(bytes);
      let has2 = i + 2 < Array.size(bytes);
      let b1 = if (has1) Nat8.toNat(bytes[i + 1]) else 0;
      let b2 = if (has2) Nat8.toNat(bytes[i + 2]) else 0;

      let i0 = b0 / 4;
      let i1 = (b0 % 4) * 16 + (b1 / 16);
      let i2 = (b1 % 16) * 4 + (b2 / 64);
      let i3 = b2 % 64;

      out.add(Text.fromChar(char_at(table, i0)));
      out.add(Text.fromChar(char_at(table, i1)));
      out.add(if (has1) Text.fromChar(char_at(table, i2)) else "=");
      out.add(if (has2) Text.fromChar(char_at(table, i3)) else "=");

      i += 3;
    };
    Text.join("", out.vals())
  };

  func char_at(text : Text, idx : Nat) : Char {
    var i : Nat = 0;
    for (c in text.chars()) {
      if (i == idx) return c;
      i += 1;
    };
    'A'
  };
}

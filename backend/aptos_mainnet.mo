import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Int "mo:base/Int";
import MoError "mo:base/Error";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Addressing "./addressing";
import AppConfig "./config/app_config";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import SHA3 "./sha3";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.APTOS_MAINNET;
  let APT_DECIMALS : Nat8 = 8;
  let APTOS_COIN_TYPE : Text = "0x1::aptos_coin::AptosCoin";
  let APTOS_TRANSFER_COINS_FN : Text = "0x1::aptos_account::transfer_coins";

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

  type ManagedAptosIdentity = {
    address : Text;
    pubkey : [Nat8];
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
              "unexpected ed25519 public key length for Aptos address: " #
              Nat.toText(pubkey.size())
            )
          );
        };

        let hasher = SHA3.Sha3(256);
        hasher.update(Array.append<Nat8>(pubkey, [0 : Nat8]));
        let auth_key = hasher.finalize();

        #Ok({
          network = NETWORK_NAME;
          address = "0x" # Addressing.hex_encode(auth_key);
          public_key_hex = Addressing.hex_encode(pubkey);
          key_name;
          message = ?"Aptos account address (auth key from ed25519 pubkey)";
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
    let accountRaw = Text.trim(req.account, #char ' ');
    if (Text.size(accountRaw) == 0) {
      return #Err(#InvalidInput("account is required"));
    };
    let tokenTypeOpt : ?Text = switch (req.token) {
      case (?token) {
        let t = Text.trim(token, #char ' ');
        if (Text.size(t) == 0) null else ?normalize_type_tag(t);
      };
      case null null;
    };
    let isNative = (tokenTypeOpt == null);
    let coinType = switch (tokenTypeOpt) {
      case (?t) t;
      case null "0x1::aptos_coin::AptosCoin";
    };
    let resourceType = "0x1::coin::CoinStore<" # coinType # ">";

    let account = switch (normalize_aptos_address(accountRaw)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("aptos rpc url resolution failed: " # msg));
    };
    let path = "/accounts/" # path_encode(account) # "/resource/" # path_encode(resourceType);
    let httpRes = switch (await Outcall.get_json(rpcUrl # path, aptos_rpc_max_response_bytes_for_path(#get, path), "aptos rpc")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    let decimals : Nat8 = if (isNative) {
      APT_DECIMALS
    } else {
      switch (await fetch_coin_decimals(rpcUrl, coinType)) {
        case (?d) d;
        case null APT_DECIMALS;
      }
    };
    let tokenResp : ?Text = if (isNative) null else ?coinType;
    let missingMsg = if (isNative) {
      "Aptos CoinStore resource not found (treating balance as 0)"
    } else {
      "Aptos token CoinStore resource not found (treating balance as 0)"
    };

    if (httpRes.status == 404) {
      return #Ok({
        network = NETWORK_NAME;
        account;
        token = tokenResp;
        amount = ?"0";
        decimals = ?decimals;
        block_ref = null;
        pending = false;
        message = ?missingMsg;
      });
    };

    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("aptos rpc response is not utf-8"));
    };

    if (httpRes.status != 200 and httpRes.status != 201) {
      return #Err(#Internal("aptos http status " # Nat.toText(httpRes.status) # ": " # truncate_text(payloadText, 300)));
    };

    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse aptos response failed"));
    };

    switch (json_object_field(payload, "error_code")) {
      case (?#String(code)) {
        if (code == "resource_not_found") {
          return #Ok({
            network = NETWORK_NAME;
            account;
            token = tokenResp;
            amount = ?"0";
            decimals = ?decimals;
            block_ref = null;
            pending = false;
            message = ?missingMsg;
          });
        };
        return #Err(#Internal("Aptos REST error: " # truncate_text(JsonAst.show(payload), 300)));
      };
      case (_) {};
    };

    let dataObj = switch (json_object_field(payload, "data")) {
      case (?v) v;
      case null return #Err(#Internal("Aptos CoinStore missing data"));
    };
    let coinObj = switch (json_object_field(dataObj, "coin")) {
      case (?v) v;
      case null return #Err(#Internal("Aptos CoinStore missing data.coin"));
    };
    let valueText = switch (json_object_field(coinObj, "value")) {
      case (?#String(s)) s;
      case (_) return #Err(#Internal("Aptos CoinStore missing data.coin.value"));
    };
    let amountRaw = switch (nat_from_decimal_text(valueText)) {
      case (?v) v;
      case null return #Err(#Internal("Aptos coin value parse failed"));
    };

    #Ok({
      network = NETWORK_NAME;
      account;
      token = tokenResp;
      amount = ?format_units(amountRaw, Nat8.toNat(decimals));
      decimals = ?decimals;
      block_ref = null;
      pending = false;
      message = ?(if (isNative) "Aptos REST CoinStore resource" else "Aptos REST token CoinStore resource");
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

    let managed = switch (await fetch_managed_aptos_identity()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    switch (req.from) {
      case (?fromText) {
        let fromTrimmed = Text.trim(fromText, #char ' ');
        if (Text.size(fromTrimmed) > 0) {
          let normalizedFrom = switch (normalize_aptos_address(fromTrimmed)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          if (normalizedFrom != managed.address) {
            return #Err(#InvalidInput("from does not match canister-managed Aptos address"));
          };
        };
      };
      case null {};
    };

    let to = switch (normalize_aptos_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let coinType = switch (req.token) {
      case (?tokenText) {
        let t = Text.trim(tokenText, #char ' ');
        if (Text.size(t) == 0) APTOS_COIN_TYPE else normalize_type_tag(t);
      };
      case null APTOS_COIN_TYPE;
    };
    let isNative = (coinType == APTOS_COIN_TYPE);
    let decimals : Nat8 = if (isNative) {
      APT_DECIMALS
    } else {
      switch (await fetch_coin_decimals_from_rest(coinType, rpcOverride)) {
        case (?d) d;
        case null APT_DECIMALS;
      }
    };

    let amountUnits = switch (parse_decimal_units(req.amount, Nat8.toNat(decimals))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountUnits == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };
    let amountU64 = switch (nat_to_u64(amountUnits)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let accountInfo = switch (await aptos_get_json_with_rpc(rpcOverride, "/accounts/" # path_encode(managed.address))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let sequenceNumber = switch (json_string_field(accountInfo, "sequence_number")) {
      case (?s) s;
      case null return #Err(#Internal("Aptos account missing sequence_number"));
    };

    let ledgerInfo = switch (await aptos_get_json_with_rpc(rpcOverride, "/")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let chainIdNat = switch (json_nat_value_field(ledgerInfo, "chain_id")) {
      case (?n) n;
      case null return #Err(#Internal("Aptos ledger info missing chain_id"));
    };
    if (chainIdNat > 255) {
      return #Err(#Internal("Aptos chain_id is out of range"));
    };

    let gasInfo = switch (await aptos_get_json_with_rpc(rpcOverride, "/estimate_gas_price")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let gasUnitPrice = switch (json_nat_value_field(gasInfo, "gas_estimate")) {
      case (?n) n;
      case null switch (json_nat_value_field(gasInfo, "deprioritized_gas_estimate")) {
        case (?n2) n2;
        case null 100;
      };
    };
    let maxGasAmount : Nat = if (isNative) 20_000 else 80_000;
    let expiration : Nat = (Int.abs(Time.now()) / 1_000_000_000) + 600;

    let payloadJson =
      "{" #
      "\"type\":\"entry_function_payload\"," #
      "\"function\":" # json_quote(APTOS_TRANSFER_COINS_FN) # "," #
      "\"type_arguments\":[" # json_quote(coinType) # "]," #
      "\"arguments\":[" # json_quote(to) # "," # json_quote(Nat.toText(amountU64)) # "]" #
      "}";

    let rawTxReqJson =
      "{" #
      "\"sender\":" # json_quote(managed.address) # "," #
      "\"sequence_number\":" # json_quote(sequenceNumber) # "," #
      "\"max_gas_amount\":" # json_quote(Nat.toText(maxGasAmount)) # "," #
      "\"gas_unit_price\":" # json_quote(Nat.toText(gasUnitPrice)) # "," #
      "\"expiration_timestamp_secs\":" # json_quote(Nat.toText(expiration)) # "," #
      "\"payload\":" # payloadJson # "," #
      "\"chain_id\":" # Nat.toText(chainIdNat) #
      "}";

    let signingMessageResp = switch (await aptos_post_json_with_rpc(rpcOverride, "/transactions/signing_message", rawTxReqJson)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signingMessageHex = switch (json_string_field(signingMessageResp, "message")) {
      case (?s) s;
      case null return #Err(#Internal("Aptos signing_message missing message"));
    };
    let signingMessageBytes = switch (decode_hex_prefixed(signingMessageHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signature = switch (await sign_aptos_message(signingMessageBytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let submitReqJson =
      "{" #
      "\"sender\":" # json_quote(managed.address) # "," #
      "\"sequence_number\":" # json_quote(sequenceNumber) # "," #
      "\"max_gas_amount\":" # json_quote(Nat.toText(maxGasAmount)) # "," #
      "\"gas_unit_price\":" # json_quote(Nat.toText(gasUnitPrice)) # "," #
      "\"expiration_timestamp_secs\":" # json_quote(Nat.toText(expiration)) # "," #
      "\"payload\":" # payloadJson # "," #
      "\"chain_id\":" # Nat.toText(chainIdNat) # "," #
      "\"signature\":{" #
        "\"type\":\"ed25519_signature\"," #
        "\"public_key\":" # json_quote("0x" # Addressing.hex_encode(managed.pubkey)) # "," #
        "\"signature\":" # json_quote("0x" # Addressing.hex_encode(signature)) #
      "}" #
      "}";

    let submitResp = switch (await aptos_post_json_with_rpc(rpcOverride, "/transactions", submitReqJson)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let txHash = json_string_field(submitResp, "hash");
    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = txHash;
      message = switch (txHash) {
        case (?h) "Aptos submit accepted: " # h;
        case null "Aptos submit accepted";
      };
    })
  };

  public func discover_coin_type_token(coin_type : Text) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let normalized = normalize_type_tag(coin_type);
    if (Text.size(Text.trim(normalized, #char ' ')) == 0) {
      return #Err(#InvalidInput("coin type is required"));
    };
    let owner = switch (split_once_double_colon(normalized)) {
      case (?(left, _)) left;
      case null return #Err(#InvalidInput("coin type is invalid"));
    };
    let resourceType = "0x1::coin::CoinInfo<" # normalized # ">";
    let info = switch (await aptos_get_json("/accounts/" # path_encode(owner) # "/resource/" # path_encode(resourceType))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let dataObj = switch (json_object_field(info, "data")) {
      case (?v) v;
      case null return #Err(#Internal("Aptos CoinInfo missing data"));
    };
    let decimalsNat = switch (json_nat_value_field(dataObj, "decimals")) {
      case (?n) n;
      case null return #Err(#Internal("Aptos CoinInfo missing decimals"));
    };
    if (decimalsNat > 255) {
      return #Err(#Internal("Aptos CoinInfo missing decimals"));
    };
    let symbol = switch (json_string_field(dataObj, "symbol")) {
      case (?s) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) return #Err(#Internal("Aptos CoinInfo missing symbol"));
        t
      };
      case null return #Err(#Internal("Aptos CoinInfo missing symbol"));
    };
    let name = switch (json_string_field(dataObj, "name")) {
      case (?s) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) symbol else t
      };
      case null symbol;
    };
    #Ok({
      network = NETWORK_NAME;
      symbol;
      name;
      token_address = normalized;
      decimals = decimalsNat;
    })
  };

  func fetch_managed_aptos_identity() : async Error.WalletResult<ManagedAptosIdentity> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((pubkey, _))) {
        if (pubkey.size() != 32) {
          return #Err(
            #Internal(
              "unexpected ed25519 public key length for Aptos signer: " # Nat.toText(pubkey.size())
            )
          );
        };
        let address = switch (aptos_address_from_pubkey(pubkey)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        #Ok({ address; pubkey })
      };
    }
  };

  func aptos_address_from_pubkey(pubkey : [Nat8]) : Error.WalletResult<Text> {
    if (pubkey.size() != 32) {
      return #Err(#InvalidInput("Aptos pubkey must be 32 bytes"));
    };
    let hasher = SHA3.Sha3(256);
    hasher.update(Array.append<Nat8>(pubkey, [0 : Nat8]));
    let authKey = hasher.finalize();
    #Ok("0x" # Addressing.hex_encode(authKey))
  };

  func normalize_aptos_address(input : Text) : Error.WalletResult<Text> {
    let s = Text.trim(input, #char ' ');
    if (Text.size(s) == 0) {
      return #Err(#InvalidInput("Aptos address is required"));
    };
    let noPrefix = switch (Text.stripStart(s, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(s, #text "0X")) {
        case (?v2) v2;
        case null s;
      };
    };
    if (Text.size(noPrefix) == 0) {
      return #Err(#InvalidInput("invalid Aptos address hex"));
    };
    if (Text.size(noPrefix) > 64) {
      return #Err(#InvalidInput("Aptos address is too long"));
    };
    for (c in noPrefix.chars()) {
      if (hex_digit_value(c) == null) {
        return #Err(#InvalidInput("invalid Aptos address hex"));
      };
    };
    let lower = to_lower_hex_text(noPrefix);
    #Ok("0x" # repeat_text("0", 64 - Text.size(lower)) # lower)
  };

  func path_encode(value : Text) : Text {
    let bytes = Blob.toArray(Text.encodeUtf8(value));
    var out = "";
    for (b in bytes.vals()) {
      let n = Nat8.toNat(b);
      if (
        (n >= 48 and n <= 57) or
        (n >= 65 and n <= 90) or
        (n >= 97 and n <= 122) or
        n == 45 or n == 95 or n == 46 or n == 126
      ) {
        out #= Text.fromChar(Char.fromNat32(Nat32.fromNat(n)));
      } else {
        out #= "%" # hex_upper_digit(n / 16) # hex_upper_digit(n % 16);
      };
    };
    out
  };

  func normalize_type_tag(input : Text) : Text {
    Text.trim(input, #char ' ')
  };

  func split_once_double_colon(input : Text) : ?(Text, Text) {
    let chars = Buffer.Buffer<Char>(Text.size(input));
    for (c in input.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    if (arr.size() < 2) return null;
    var i : Nat = 0;
    while (i + 1 < arr.size()) {
      if (arr[i] == ':' and arr[i + 1] == ':') {
        var left = "";
        var j : Nat = 0;
        while (j < i) {
          left #= Text.fromChar(arr[j]);
          j += 1;
        };
        var right = "";
        j := i + 2;
        while (j < arr.size()) {
          right #= Text.fromChar(arr[j]);
          j += 1;
        };
        return ?(left, right);
      };
      i += 1;
    };
    null
  };

  func fetch_coin_decimals(rpcUrl : Text, coinType : Text) : async ?Nat8 {
    let normalized = normalize_type_tag(coinType);
    let owner = switch (split_once_double_colon(normalized)) {
      case (?(left, _)) left;
      case null return null;
    };
    let resourceType = "0x1::coin::CoinInfo<" # normalized # ">";
    let path = "/accounts/" # path_encode(owner) # "/resource/" # path_encode(resourceType);
    let httpRes = switch (await Outcall.get_json(rpcUrl # path, aptos_rpc_max_response_bytes_for_path(#get, path), "aptos rpc")) {
      case (#Err(_)) return null;
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200 and httpRes.status != 201) return null;
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return null;
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return null;
    };
    let dataObj = switch (json_object_field(payload, "data")) {
      case (?v) v;
      case null return null;
    };
    switch (json_object_field(dataObj, "decimals")) {
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

  func fetch_coin_decimals_from_rest(coinType : Text, rpcOverride : ?Text) : async ?Nat8 {
    let normalized = normalize_type_tag(coinType);
    let owner = switch (split_once_double_colon(normalized)) {
      case (?(left, _)) left;
      case null return null;
    };
    let resourceType = "0x1::coin::CoinInfo<" # normalized # ">";
    let path = "/accounts/" # path_encode(owner) # "/resource/" # path_encode(resourceType);
    let v = switch (await aptos_get_json_with_rpc(rpcOverride, path)) {
      case (#Err(_)) return null;
      case (#Ok(x)) x;
    };
    switch (json_nat_value_field(switch (json_object_field(v, "data")) { case (?d) d; case null return null; }, "decimals")) {
      case (?n) { if (n > 255) null else ?Nat8.fromNat(n) };
      case null null;
    }
  };

  func sign_aptos_message(message : [Nat8]) : async Error.WalletResult<[Nat8]> {
    let args : SignWithSchnorrArgs = {
      message = Blob.fromArray(message);
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
        return #Err(#Internal("unexpected Aptos signature length: " # Nat.toText(sig.size())));
      };
      #Ok(sig)
    } catch e {
      #Err(#Internal("Aptos sign_with_schnorr failed: " # MoError.message(e)))
    }
  };

  func aptos_get_json(path : Text) : async Error.WalletResult<JsonAst.JSON> {
    await aptos_get_json_with_rpc(null, path)
  };

  func aptos_get_json_with_rpc(rpcOverride : ?Text, path : Text) : async Error.WalletResult<JsonAst.JSON> {
    await aptos_http_json(#get, path, null, rpcOverride)
  };

  func aptos_post_json(path : Text, bodyText : Text) : async Error.WalletResult<JsonAst.JSON> {
    await aptos_post_json_with_rpc(null, path, bodyText)
  };

  func aptos_post_json_with_rpc(rpcOverride : ?Text, path : Text, bodyText : Text) : async Error.WalletResult<JsonAst.JSON> {
    await aptos_http_json(#post, path, ?bodyText, rpcOverride)
  };

  func aptos_http_json(
    _method : Outcall.HttpMethod,
    path : Text,
    bodyText : ?Text,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let base = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) Text.trimEnd(url, #char '/');
      case (#err(msg)) return #Err(#Internal("aptos rpc url resolution failed: " # msg));
    };
    let url = base # path;
    let httpRes = switch (bodyText) {
      case (?body) {
        switch (await Outcall.post_json(url, Text.encodeUtf8(body), aptos_rpc_max_response_bytes_for_path(#post, path), "aptos rpc")) {
          case (#Err(err)) return #Err(err);
          case (#Ok(resp)) resp;
        }
      };
      case null {
        switch (await Outcall.get_json(url, aptos_rpc_max_response_bytes_for_path(#get, path), "aptos rpc")) {
          case (#Err(err)) return #Err(err);
          case (#Ok(resp)) resp;
        }
      };
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("aptos rpc response is not utf-8"));
    };
    let parsed = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse aptos response failed"));
    };
    if (httpRes.status != 200 and httpRes.status != 201) {
      return #Err(#Internal(
        "aptos http status " # Nat.toText(httpRes.status) # ": " # truncate_text(JsonAst.show(parsed), 300)
      ));
    };
    switch (json_object_field(parsed, "error_code")) {
      case (?_) return #Err(#Internal("Aptos REST error: " # truncate_text(JsonAst.show(parsed), 300)));
      case null {};
    };
    #Ok(parsed)
  };

  func aptos_rpc_max_response_bytes_for_path(method : Outcall.HttpMethod, path : Text) : Nat64 {
    if (path == "/") return 16 * 1024 : Nat64;
    if (path == "/estimate_gas_price") return 16 * 1024 : Nat64;
    if (path == "/transactions/signing_message") return 64 * 1024 : Nat64;
    if (path == "/transactions") {
      switch (method) {
        case (#post) return 128 * 1024 : Nat64;
        case (#get) return 64 * 1024 : Nat64;
        case (_) return 128 * 1024 : Nat64;
      }
    };
    if (Text.startsWith(path, #text "/accounts/") and Text.contains(path, #text "/resource/")) {
      return 64 * 1024 : Nat64;
    };
    if (Text.startsWith(path, #text "/accounts/")) return 32 * 1024 : Nat64;
    128 * 1024 : Nat64
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

  func nat_to_u64(n : Nat) : Error.WalletResult<Nat> {
    if (n > 18_446_744_073_709_551_615) {
      #Err(#InvalidInput("amount is too large"))
    } else {
      #Ok(n)
    }
  };

  func decode_hex_prefixed(input : Text) : Error.WalletResult<[Nat8]> {
    let trimmed = Text.trim(input, #char ' ');
    let noPrefix = switch (Text.stripStart(trimmed, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(trimmed, #text "0X")) {
        case (?v2) v2;
        case null trimmed;
      };
    };
    let chars = Buffer.Buffer<Char>(Text.size(noPrefix));
    for (c in noPrefix.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    if (arr.size() % 2 != 0) return #Err(#InvalidInput("hex length must be even"));
    let out = Buffer.Buffer<Nat8>(arr.size() / 2);
    var i : Nat = 0;
    while (i + 1 < arr.size()) {
      let hi = switch (hex_digit_value(arr[i])) {
        case (?v) v;
        case null return #Err(#InvalidInput("invalid hex character"));
      };
      let lo = switch (hex_digit_value(arr[i + 1])) {
        case (?v) v;
        case null return #Err(#InvalidInput("invalid hex character"));
      };
      out.add(Nat8.fromNat((hi * 16) + lo));
      i += 2;
    };
    #Ok(Buffer.toArray(out))
  };

  func json_quote(s : Text) : Text {
    "\"" # json_escape(s) # "\""
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

  func json_nat_value_field(value : JsonAst.JSON, key : Text) : ?Nat {
    switch (json_object_field(value, key)) {
      case (?v) json_nat_value(v);
      case null null;
    }
  };

  func hex_upper_digit(v : Nat) : Text {
    if (v < 10) {
      Text.fromChar(Char.fromNat32(Nat32.fromNat(48 + v)))
    } else {
      Text.fromChar(Char.fromNat32(Nat32.fromNat(65 + (v - 10))))
    }
  };

  func hex_digit_value(c : Char) : ?Nat {
    let n = Char.toNat32(c);
    if (n >= 48 and n <= 57) return ?Nat32.toNat(n - 48);
    if (n >= 65 and n <= 70) return ?Nat32.toNat(n - 55);
    if (n >= 97 and n <= 102) return ?Nat32.toNat(n - 87);
    null
  };

  func to_lower_hex_text(t : Text) : Text {
    var out = "";
    for (c in t.chars()) {
      let n = Char.toNat32(c);
      if (n >= 65 and n <= 70) {
        out #= Text.fromChar(Char.fromNat32(n + 32));
      } else {
        out #= Text.fromChar(c);
      };
    };
    out
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

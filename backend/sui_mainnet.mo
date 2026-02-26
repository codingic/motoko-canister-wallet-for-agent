import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Int "mo:base/Int";
import MoError "mo:base/Error";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Addressing "./addressing";
import AppConfig "./config/app_config";
import Blake2b "./blake2b";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.SUI_MAINNET;
  let SUI_DECIMALS : Nat8 = 9;
  let SUI_ED25519_FLAG : Nat8 = 0x00;
  let SUI_COIN_TYPE : Text = "0x2::sui::SUI";
  let SUI_DEFAULT_GAS_BUDGET_NATIVE : Nat = 2_000_000;
  let SUI_DEFAULT_GAS_BUDGET_TOKEN : Nat = 5_000_000;

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

  type ManagedSuiIdentity = {
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
        let address = switch (sui_address_from_pubkey(pubkey)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        #Ok({
          network = NETWORK_NAME;
          address;
          public_key_hex = Addressing.hex_encode(pubkey);
          key_name;
          message = ?"Sui address from blake2b(flag||ed25519_pubkey)";
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
    let account = switch (normalize_sui_address(accountRaw)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let tokenOpt : ?Text = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) null else ?trimmed;
      };
      case null null;
    };
    let paramsJson = switch (tokenOpt) {
      case (?coinType) {
        "[\"" # json_escape(account) # "\",\"" # json_escape(coinType) # "\"]"
      };
      case null {
        "[\"" # json_escape(account) # "\"]"
      };
    };
    let result = switch (await sui_rpc_call("suix_getBalance", paramsJson, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let totalRawText = switch (json_object_field(result, "totalBalance")) {
      case (?#String(s)) s;
      case (?#Number(n)) {
        if (n < 0) return #Err(#Internal("sui totalBalance is negative"));
        Int.toText(n)
      };
      case (_) return #Err(#Internal("sui balance missing totalBalance"));
    };
    let totalRaw = switch (nat_from_decimal_text(totalRawText)) {
      case (?v) v;
      case null return #Err(#Internal("sui totalBalance parse failed"));
    };
    let decimals : Nat8 = switch (tokenOpt) {
      case (?coinType) {
        switch (await fetch_coin_decimals(coinType, rpcOverride)) {
          case (?v) v;
          case null SUI_DECIMALS;
        }
      };
      case null SUI_DECIMALS;
    };

    #Ok({
      network = NETWORK_NAME;
      account;
      token = tokenOpt;
      amount = ?format_units(totalRaw, Nat8.toNat(decimals));
      decimals = ?decimals;
      block_ref = null;
      pending = false;
      message = ?"Sui JSON-RPC suix_getBalance";
    })
  };

  public func transfer_sui(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) > 0) {
          return #Err(#InvalidInput("sui_mainnet_transfer_sui does not accept token parameter"));
        };
      };
      case null {};
    };
    await transfer_impl(req, null)
  };

  public func transfer_token(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) == 0) {
          return #Err(#InvalidInput("token is required for sui token transfer"));
        };
      };
      case null return #Err(#InvalidInput("token is required for sui token transfer"));
    };
    await transfer_impl(req, null)
  };

  public func transfer_sui_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) > 0) {
          return #Err(#InvalidInput("sui_mainnet_transfer_sui does not accept token parameter"));
        };
      };
      case null {};
    };
    await transfer_impl(req, rpcOverride)
  };

  public func transfer_token_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) == 0) {
          return #Err(#InvalidInput("token is required for sui token transfer"));
        };
      };
      case null return #Err(#InvalidInput("token is required for sui token transfer"));
    };
    await transfer_impl(req, rpcOverride)
  };

  public func discover_coin_type_token(coin_type : Text) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let coinType = Text.trim(coin_type, #char ' ');
    if (Text.size(coinType) == 0) {
      return #Err(#InvalidInput("coin type is required"));
    };

    let result = switch (await sui_rpc_call(
      "suix_getCoinMetadata",
      "[\"" # json_escape(coinType) # "\"]",
      null,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (result) {
      case (#Null) return #Err(#Internal("Sui coin metadata not found"));
      case (_) {};
    };

    let decimals : Nat8 = switch (json_object_field(result, "decimals")) {
      case (?#Number(n)) {
        if (n < 0 or n > 255) return #Err(#Internal("Sui coin metadata missing decimals"));
        Nat8.fromNat(Int.abs(n))
      };
      case (?#String(s)) {
        switch (nat_from_decimal_text(s)) {
          case (?v) {
            if (v > 255) return #Err(#Internal("Sui coin metadata missing decimals"));
            Nat8.fromNat(v)
          };
          case null return #Err(#Internal("Sui coin metadata missing decimals"));
        }
      };
      case (_) return #Err(#Internal("Sui coin metadata missing decimals"));
    };

    let symbol = switch (json_string_field(result, "symbol")) {
      case (?s) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) return #Err(#Internal("Sui coin metadata missing symbol"));
        t
      };
      case null return #Err(#Internal("Sui coin metadata missing symbol"));
    };
    let name = switch (json_string_field(result, "name")) {
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
      token_address = coinType;
      decimals = Nat8.toNat(decimals);
    })
  };

  func fetch_coin_decimals(coinType : Text, rpcOverride : ?Text) : async ?Nat8 {
    let result = switch (await sui_rpc_call(
      "suix_getCoinMetadata",
      "[\"" # json_escape(Text.trim(coinType, #char ' ')) # "\"]",
      rpcOverride,
    )) {
      case (#Err(_)) return null;
      case (#Ok(v)) v;
    };
    switch (result) {
      case (#Null) return null;
      case (_) {};
    };
    switch (json_object_field(result, "decimals")) {
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

  func transfer_impl(req : Types.TransferRequest, rpcOverride : ?Text) : async Error.WalletResult<Types.TransferResponse> {
    if (Text.size(Text.trim(req.to, #char ' ')) == 0) {
      return #Err(#InvalidInput("to is required"));
    };
    if (Text.size(Text.trim(req.amount, #char ' ')) == 0) {
      return #Err(#InvalidInput("amount is required"));
    };

    let managed = switch (await fetch_managed_sui_identity()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    switch (req.from) {
      case (?fromText) {
        let fromTrimmed = Text.trim(fromText, #char ' ');
        if (Text.size(fromTrimmed) > 0) {
          let normalizedFrom = switch (normalize_sui_address(fromTrimmed)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          if (normalizedFrom != managed.address) {
            return #Err(#InvalidInput("from does not match canister-managed Sui address"));
          };
        };
      };
      case null {};
    };

    let to = switch (normalize_sui_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let coinTypeOpt : ?Text = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) null else ?trimmed;
      };
      case null null;
    };
    let decimals : Nat8 = switch (coinTypeOpt) {
      case (?coinType) {
        switch (await fetch_coin_decimals(coinType, rpcOverride)) {
          case (?v) v;
          case null SUI_DECIMALS;
        }
      };
      case null SUI_DECIMALS;
    };
    let amount = switch (parse_decimal_units(req.amount, Nat8.toNat(decimals))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amount == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };
    let amountU64 = switch (nat_to_u64(amount)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let gasPrice : Nat = switch (await sui_rpc_call("suix_getReferenceGasPrice", "[]", rpcOverride)) {
      case (#Err(_)) 1000;
      case (#Ok(v)) {
        switch (json_nat_value(v)) {
          case (?n) n;
          case null 1000;
        }
      };
    };
    let gasBudget : Nat = switch (coinTypeOpt) {
      case (?_) SUI_DEFAULT_GAS_BUDGET_TOKEN;
      case null SUI_DEFAULT_GAS_BUDGET_NATIVE;
    };

    let txBytesB64 = switch (coinTypeOpt) {
      case (?coinType) {
        let tokenCoins = switch (await fetch_sui_coin_ids(managed.address, coinType, amountU64, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let gasCoin = switch (await select_sui_gas_coin(managed.address, gasBudget, gasPrice, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let params =
          "[" # json_quote(managed.address) # "," #
          json_array_texts(tokenCoins) # "," #
          json_array_texts([to]) # "," #
          json_array_texts([Nat.toText(amountU64)]) # "," #
          json_quote(gasCoin) # "," #
          json_quote(Nat.toText(gasBudget)) # "]";
        let built = switch (await sui_rpc_call("unsafe_pay", params, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        switch (extract_sui_tx_bytes(built)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
      case null {
        let needed = amountU64 + (gasBudget * gasPrice);
        let suiCoins = switch (await fetch_sui_coin_ids(managed.address, SUI_COIN_TYPE, needed, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let params =
          "[" # json_quote(managed.address) # "," #
          json_array_texts(suiCoins) # "," #
          json_array_texts([to]) # "," #
          json_array_texts([Nat.toText(amountU64)]) # "," #
          json_quote(Nat.toText(gasBudget)) # "]";
        let built = switch (await sui_rpc_call("unsafe_paySui", params, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        switch (extract_sui_tx_bytes(built)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
    };

    let txBytes = switch (base64_decode_std(txBytesB64)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let digest32 = switch (sui_intent_digest(txBytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let sig = switch (await sign_sui_digest(digest32)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let suiSig = Array.append<Nat8>(Array.append<Nat8>([SUI_ED25519_FLAG], sig), managed.pubkey);
    let suiSigB64 = base64_encode_std_nopad(suiSig);

    let execParams =
      "[" # json_quote(txBytesB64) # "," #
      json_array_texts([suiSigB64]) # "," #
      "{\"showEffects\":true},\"WaitForLocalExecution\"]";
    let execRes = switch (await sui_rpc_call("sui_executeTransactionBlock", execParams, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let statusText : ?Text = switch (json_object_field(execRes, "effects")) {
      case (?effectsObj) {
        switch (json_object_field(effectsObj, "status")) {
          case (?statusObj) {
            switch (json_object_field(statusObj, "status")) {
              case (?#String(s)) ?s;
              case (_) null;
            }
          };
          case null null;
        }
      };
      case null null;
    };
    switch (statusText) {
      case (?s) {
        if (s != "success") {
          let errText : Text = switch (json_object_field(execRes, "effects")) {
            case (?effectsObj) {
              switch (json_object_field(effectsObj, "status")) {
                case (?statusObj) {
                  switch (json_object_field(statusObj, "error")) {
                    case (?#String(e)) e;
                    case (?v) JsonAst.show(v);
                    case null "unknown error";
                  }
                };
                case null "unknown error";
              }
            };
            case null "unknown error";
          };
          return #Err(#Internal("Sui executeTransactionBlock failed: " # errText));
        };
      };
      case null {};
    };

    let txId = switch (json_object_field(execRes, "digest")) {
      case (?#String(s)) ?s;
      case (_) null;
    };
    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = txId;
      message = switch (txId) {
        case (?h) "Sui executeTransactionBlock accepted: " # h;
        case null "Sui executeTransactionBlock accepted";
      };
    })
  };

  func fetch_managed_sui_identity() : async Error.WalletResult<ManagedSuiIdentity> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((pubkey, _key_name))) {
        let address = switch (sui_address_from_pubkey(pubkey)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        #Ok({ address; pubkey })
      };
    }
  };

  func fetch_sui_coin_ids(
    owner : Text,
    coinType : Text,
    needed : Nat,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<[Text]> {
    let params =
      "[" # json_quote(owner) # "," # json_quote(Text.trim(coinType, #char ' ')) # ",null,100]";
    let v = switch (await sui_rpc_call("suix_getCoins", params, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(x)) x;
    };
    let dataArr = switch (json_object_field(v, "data")) {
      case (?#Array(items)) items;
      case (_) return #Err(#Internal("Sui suix_getCoins missing data"));
    };
    let selected = Buffer.Buffer<Text>(dataArr.size());
    var total : Nat = 0;
    for (item in dataArr.vals()) {
      let id = switch (json_string_field(item, "coinObjectId")) {
        case (?s) s;
        case null return #Err(#Internal("Sui coin item missing coinObjectId"));
      };
      let bal = switch (json_object_field(item, "balance")) {
        case (?balJson) {
          switch (json_nat_value(balJson)) {
            case (?n) n;
            case null 0;
          }
        };
        case null 0;
      };
      selected.add(id);
      total += bal;
      if (total >= needed) {
        return #Ok(Buffer.toArray(selected));
      };
    };
    #Err(#Internal(
      "insufficient Sui coin objects for " # coinType # ": need " # Nat.toText(needed) #
      ", found " # Nat.toText(total)
    ))
  };

  func select_sui_gas_coin(owner : Text, gasBudget : Nat, gasPrice : Nat, rpcOverride : ?Text) : async Error.WalletResult<Text> {
    let need = gasBudget * gasPrice;
    let v = switch (await sui_rpc_call(
      "suix_getCoins",
      "[" # json_quote(owner) # "," # json_quote(SUI_COIN_TYPE) # ",null,50]",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(x)) x;
    };
    let dataArr = switch (json_object_field(v, "data")) {
      case (?#Array(items)) items;
      case (_) return #Err(#Internal("Sui suix_getCoins missing data"));
    };
    var bestId : ?Text = null;
    var bestBal : Nat = 0;
    for (item in dataArr.vals()) {
      let id = switch (json_string_field(item, "coinObjectId")) {
        case (?s) s;
        case null "";
      };
      let bal = switch (json_object_field(item, "balance")) {
        case (?balJson) {
          switch (json_nat_value(balJson)) {
            case (?n) n;
            case null 0;
          }
        };
        case null 0;
      };
      if (bal >= need and Text.size(id) > 0) {
        switch (bestId) {
          case (?_) {
            if (bal > bestBal) {
              bestId := ?id;
              bestBal := bal;
            };
          };
          case null {
            bestId := ?id;
            bestBal := bal;
          };
        };
      };
    };
    switch (bestId) {
      case (?id) #Ok(id);
      case null #Err(#Internal(
        "no SUI gas coin covers required gas budget " # Nat.toText(gasBudget) #
        " @ price " # Nat.toText(gasPrice)
      ));
    }
  };

  func extract_sui_tx_bytes(v : JsonAst.JSON) : Error.WalletResult<Text> {
    switch (json_string_field(v, "txBytes")) {
      case (?s) #Ok(s);
      case null {
        switch (json_string_field(v, "tx_bytes")) {
          case (?s2) #Ok(s2);
          case null #Err(#Internal("Sui unsafe_* response missing txBytes"));
        }
      };
    }
  };

  func sui_address_from_pubkey(pubkey32 : [Nat8]) : Error.WalletResult<Text> {
    if (pubkey32.size() != 32) {
      return #Err(#InvalidInput("Sui pubkey must be 32 bytes"));
    };
    let digest = switch (Blake2b.hash256(Array.append<Nat8>([SUI_ED25519_FLAG], pubkey32))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok("0x" # Addressing.hex_encode(digest))
  };

  func sui_intent_digest(txBytes : [Nat8]) : Error.WalletResult<[Nat8]> {
    switch (Blake2b.hash256(Array.append<Nat8>([0, 0, 0], txBytes))) {
      case (#Err(err)) #Err(err);
      case (#Ok(v)) {
        if (v.size() == 32) #Ok(v) else #Err(#Internal("unexpected Sui intent digest length"))
      };
    }
  };

  func sign_sui_digest(digest32 : [Nat8]) : async Error.WalletResult<[Nat8]> {
    if (digest32.size() != 32) {
      return #Err(#Internal("Sui signing digest must be 32 bytes"));
    };
    let args : SignWithSchnorrArgs = {
      message = Blob.fromArray(digest32);
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
        return #Err(#Internal("unexpected Sui signature length: " # Nat.toText(sig.size())));
      };
      #Ok(sig)
    } catch e {
      #Err(#Internal("sign_with_schnorr failed: " # MoError.message(e)))
    }
  };

  func nat_to_u64(n : Nat) : Error.WalletResult<Nat> {
    if (n > 18_446_744_073_709_551_615) {
      #Err(#InvalidInput("amount is too large"))
    } else {
      #Ok(n)
    }
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
      };
    };
    var pad = fracDigits;
    while (pad < decimals) {
      acc *= 10;
      pad += 1;
    };
    #Ok(acc)
  };

  func json_quote(s : Text) : Text {
    "\"" # json_escape(s) # "\""
  };

  func json_array_texts(items : [Text]) : Text {
    var out = "[";
    var first = true;
    for (x in items.vals()) {
      if (first) {
        first := false;
      } else {
        out #= ",";
      };
      out #= json_quote(x);
    };
    out # "]"
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

  func base64_encode_std_nopad(data : [Nat8]) : Text {
    let alphabet : [Char] = [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
      'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
      'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
      'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/',
    ];
    if (data.size() == 0) return "";
    var out = "";
    var i : Nat = 0;
    while (i + 3 <= data.size()) {
      let n =
        (Nat8.toNat(data[i]) * 65_536) +
        (Nat8.toNat(data[i + 1]) * 256) +
        Nat8.toNat(data[i + 2]);
      out #= Text.fromChar(alphabet[(n / 262_144) % 64]);
      out #= Text.fromChar(alphabet[(n / 4_096) % 64]);
      out #= Text.fromChar(alphabet[(n / 64) % 64]);
      out #= Text.fromChar(alphabet[n % 64]);
      i += 3;
    };
    let rem = data.size() - i;
    if (rem == 1) {
      let n = Nat8.toNat(data[i]) * 65_536;
      out #= Text.fromChar(alphabet[(n / 262_144) % 64]);
      out #= Text.fromChar(alphabet[(n / 4_096) % 64]);
    } else if (rem == 2) {
      let n = (Nat8.toNat(data[i]) * 65_536) + (Nat8.toNat(data[i + 1]) * 256);
      out #= Text.fromChar(alphabet[(n / 262_144) % 64]);
      out #= Text.fromChar(alphabet[(n / 4_096) % 64]);
      out #= Text.fromChar(alphabet[(n / 64) % 64]);
    };
    out
  };

  func base64_decode_std(input : Text) : Error.WalletResult<[Nat8]> {
    let raw = Blob.toArray(Text.encodeUtf8(Text.trim(input, #char ' ')));
    let filtered = Buffer.Buffer<Nat8>(raw.size() + 4);
    for (b in raw.vals()) {
      if (b != 32 and b != 10 and b != 13 and b != 9) {
        filtered.add(b);
      };
    };
    while ((filtered.size() % 4) != 0) {
      filtered.add(61); // '='
    };
    let arr = Buffer.toArray(filtered);
    let out = Buffer.Buffer<Nat8>(arr.size() / 4 * 3);
    var i : Nat = 0;
    while (i < arr.size()) {
      let c0 = switch (b64_val(arr[i])) { case (?v) v; case null return #Err(#InvalidInput("invalid base64 character")) };
      let c1 = switch (b64_val(arr[i + 1])) { case (?v) v; case null return #Err(#InvalidInput("invalid base64 character")) };
      let c2 = if (arr[i + 2] == 61) 0 else switch (b64_val(arr[i + 2])) { case (?v) v; case null return #Err(#InvalidInput("invalid base64 character")) };
      let c3 = if (arr[i + 3] == 61) 0 else switch (b64_val(arr[i + 3])) { case (?v) v; case null return #Err(#InvalidInput("invalid base64 character")) };
      let n = (c0 * 262_144) + (c1 * 4_096) + (c2 * 64) + c3;
      out.add(Nat8.fromNat((n / 65_536) % 256));
      if (arr[i + 2] != 61) { out.add(Nat8.fromNat((n / 256) % 256)) };
      if (arr[i + 3] != 61) { out.add(Nat8.fromNat(n % 256)) };
      i += 4;
    };
    #Ok(Buffer.toArray(out))
  };

  func b64_val(c : Nat8) : ?Nat {
    let n = Nat8.toNat(c);
    if (n >= 65 and n <= 90) return ?(n - 65);
    if (n >= 97 and n <= 122) return ?(n - 97 + 26);
    if (n >= 48 and n <= 57) return ?(n - 48 + 52);
    if (n == 43 or n == 45) return ?62;
    if (n == 47 or n == 95) return ?63;
    if (n == 61) return ?0;
    null
  };

  func text_chars(t : Text) : [Char] {
    let buf = Buffer.Buffer<Char>(Text.size(t));
    for (c in t.chars()) { buf.add(c) };
    Buffer.toArray(buf)
  };

  func normalize_sui_address(input : Text) : Error.WalletResult<Text> {
    let s = Text.trim(input, #char ' ');
    if (Text.size(s) == 0) {
      return #Err(#InvalidInput("Sui address is required"));
    };
    let noPrefix = switch (Text.stripStart(s, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(s, #text "0X")) {
        case (?v2) v2;
        case null s;
      };
    };
    if (Text.size(noPrefix) == 0) {
      return #Err(#InvalidInput("invalid Sui address hex"));
    };
    if (Text.size(noPrefix) > 64) {
      return #Err(#InvalidInput("Sui address is too long"));
    };
    for (c in noPrefix.chars()) {
      if (hex_digit_value(c) == null) {
        return #Err(#InvalidInput("invalid Sui address hex"));
      };
    };
    let lower = to_lower_hex_text(noPrefix);
    #Ok("0x" # repeat_text("0", 64 - Text.size(lower)) # lower)
  };

  func sui_rpc_call(
    method : Text,
    paramsJson : Text,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("sui rpc url resolution failed: " # msg));
    };
    let bodyText =
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"" # json_escape(method) # "\",\"params\":" # paramsJson # "}";
    let httpRes = switch (await Outcall.post_json(
      rpcUrl,
      Text.encodeUtf8(bodyText),
      sui_rpc_max_response_bytes_for_method(method),
      "sui rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let bodySnippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 300);
        case null "<non-utf8>";
      };
      return #Err(#Internal("sui rpc http status " # Nat.toText(httpRes.status) # ": " # bodySnippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("parse sui rpc response failed: non-utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse sui rpc response failed"));
    };
    switch (json_object_field(payload, "error")) {
      case (?errObj) {
        return #Err(#Internal("Sui RPC error: " # truncate_text(JsonAst.show(errObj), 300)));
      };
      case null {};
    };
    switch (json_object_field(payload, "result")) {
      case (?v) #Ok(v);
      case null #Err(#Internal("Sui RPC missing result"));
    }
  };

  func sui_rpc_max_response_bytes_for_method(method : Text) : Nat64 {
    switch (method) {
      case ("suix_getReferenceGasPrice") 8 * 1024 : Nat64;
      case ("suix_getBalance") 16 * 1024 : Nat64;
      case ("suix_getCoinMetadata") 16 * 1024 : Nat64;
      case ("suix_getCoins") 128 * 1024 : Nat64;
      case ("unsafe_pay") 128 * 1024 : Nat64;
      case ("unsafe_paySui") 128 * 1024 : Nat64;
      case ("sui_executeTransactionBlock") 256 * 1024 : Nat64;
      case (_) 128 * 1024 : Nat64;
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
}

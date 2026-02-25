import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Addressing "./addressing";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import Sha256 "./sha256";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.TRON;
  let TRON_PREFIX : Nat8 = 0x41;
  let TRX_DECIMALS : Nat = 6;
  let TRON_FEE_LIMIT_SUN_DEFAULT : Nat = 100_000_000;

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    switch (await Addressing.fetch_ecdsa_secp256k1_public_key()) {
      case (#Err(err)) #Err(err);
      case (#Ok((public_key, key_name))) {
        switch (Addressing.evm20_from_sec1_public_key(public_key)) {
          case (#Err(err)) #Err(err);
          case (#Ok(evm20)) {
            let payload21 = Array.append<Nat8>([TRON_PREFIX], evm20);
            let checksum4 = slice_bytes(double_sha256(payload21), 0, 4);
            let address = Addressing.base58_encode(Array.append<Nat8>(payload21, checksum4));
            #Ok({
              network = NETWORK_NAME;
              address;
              public_key_hex = Addressing.hex_encode(public_key);
              key_name;
              message = ?"Derived TRON address from management canister tECDSA public key";
            })
          };
        }
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
    let parsedAccount = switch (parse_tron_address(account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    switch (tokenOpt) {
      case (?tokenText) {
        let parsedToken = switch (parse_tron_address(tokenText)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let decimals = switch (await fetch_trc20_decimals(parsedAccount, parsedToken, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let amountRaw = switch (await fetch_trc20_balance_raw(parsedAccount, parsedToken, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        return #Ok({
          network = NETWORK_NAME;
          account = parsedAccount.base58;
          token = ?parsedToken.base58;
          amount = ?format_units(amountRaw, Nat8.toNat(decimals));
          decimals = ?decimals;
          block_ref = null;
          pending = false;
          message = ?"TRON RPC triggerconstantcontract balanceOf(address)";
        });
      };
      case null {};
    };

    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("trx rpc url resolution failed: " # msg));
    };

    let bodyText = "{\"address\":\"" # json_escape(account) # "\",\"visible\":true}";
    let httpRes = switch (await Outcall.post_json(
      rpcUrl # "/wallet/getaccount",
      Text.encodeUtf8(bodyText),
      512 * 1024 : Nat64,
      "trx rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };

    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("trx rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };

    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("trx rpc response is not utf-8"));
    };

    let root = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse trx rpc response failed"));
    };

    let balanceSun : Nat = switch (json_object_field(root, "balance")) {
      case null 0;
      case (?#Number(n)) {
        if (n < 0) {
          return #Err(#Internal("TRON balance is negative"));
        };
        Int.abs(n)
      };
      case (?#String(s)) {
        switch (nat_from_decimal_text(s)) {
          case (?v) v;
          case null return #Err(#Internal("TRON balance parse failed"));
        }
      };
      case (_) return #Err(#Internal("TRON balance field has unexpected type"));
    };

    #Ok({
      network = NETWORK_NAME;
      account = parsedAccount.base58;
      token = null;
      amount = ?format_units(balanceSun, 6);
      decimals = ?6;
      block_ref = null;
      pending = false;
      message = ?"TRON RPC wallet/getaccount";
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

    let tokenOpt : ?Text = switch (req.token) {
      case (?token) {
        let t = Text.trim(token, #char ' ');
        if (Text.size(t) == 0) null else ?t;
      };
      case null null;
    };
    let to = switch (parse_tron_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let pubRes = switch (await Addressing.fetch_ecdsa_secp256k1_public_key()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let publicKeySec1 = pubRes.0;
    let managed = switch (tron_address_from_sec1_public_key(publicKeySec1)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (req.from) {
      case (?fromText) {
        let t = Text.trim(fromText, #char ' ');
        if (Text.size(t) > 0) {
          let fromAddr = switch (parse_tron_address(t)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          if (fromAddr.base58 != managed.base58) {
            return #Err(#InvalidInput("from does not match canister-managed TRON address"));
          };
        };
      };
      case null {};
    };

    let tx = switch (tokenOpt) {
      case null {
        let amountSun = switch (parse_decimal_units(req.amount, TRX_DECIMALS)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        if (amountSun == 0) return #Err(#InvalidInput("amount must be > 0"));
        let amountSunU64 = switch (nat_to_u64(amountSun)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        switch (await tron_create_trx_transfer(managed, to, amountSunU64, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
      case (?tokenText) {
        let token = switch (parse_tron_address(tokenText)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let decimals = switch (await fetch_trc20_decimals(managed, token, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let amountUnits = switch (parse_decimal_units(req.amount, Nat8.toNat(decimals))) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        if (amountUnits == 0) return #Err(#InvalidInput("amount must be > 0"));
        switch (await tron_create_trc20_transfer(managed, to, token, amountUnits, req.memo, rpcOverride)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
    };

    let txidHex = switch (json_string_field(tx, "txID")) {
      case (?s) s;
      case null return #Err(#Internal("TRON transaction response missing txID"));
    };
    let txidBytes = switch (decode_hex(txidHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (txidBytes.size() != 32) {
      return #Err(#Internal("TRON txID must be 32 bytes"));
    };
    let signatureHex = switch (await sign_tron_txid(txidBytes, publicKeySec1)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signedTx = switch (json_object_set(tx, "signature", #Array([#String(signatureHex)]))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let broadcast = switch (await tron_post_json("wallet/broadcasttransaction", JsonAst.show(signedTx), rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let accepted = switch (json_bool_field(broadcast, "result")) {
      case (?b) b;
      case null false;
    };
    if (not accepted) {
      let msg = switch (json_string_field(broadcast, "message")) {
        case (?m) decode_hex_or_passthrough(m);
        case null truncate_text(JsonAst.show(broadcast), 300);
      };
      return #Err(#Internal("TRON broadcasttransaction rejected: " # msg));
    };

    let txidFinal = switch (json_string_field(broadcast, "txid")) {
      case (?v) ?v;
      case null ?txidHex;
    };
    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = txidFinal;
      message = switch (txidFinal) {
        case (?id) "TRON broadcasttransaction accepted: " # id;
        case null "TRON broadcasttransaction accepted";
      };
    })
  };

  public func discover_trc20_token(token_address : Text) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let token = switch (parse_tron_address(token_address)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let owner = switch (await Addressing.fetch_ecdsa_secp256k1_public_key()) {
      case (#Err(err)) return #Err(err);
      case (#Ok((public_key, _))) {
        switch (tron_address_from_sec1_public_key(public_key)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
    };
    let decimals = switch (await fetch_trc20_decimals(owner, token, null)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let symbol = switch (await fetch_trc20_string_property(owner, token, "symbol()", null)) {
      case (#Ok(s)) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) "TRC" # short_suffix(token.base58) else t
      };
      case (#Err(_)) "TRC" # short_suffix(token.base58);
    };
    let name = switch (await fetch_trc20_string_property(owner, token, "name()", null)) {
      case (#Ok(s)) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) "TRC20 " # short_suffix(token.base58) else t
      };
      case (#Err(_)) "TRC20 " # short_suffix(token.base58);
    };
    #Ok({
      network = NETWORK_NAME;
      symbol;
      name;
      token_address = token.base58;
      decimals = Nat8.toNat(decimals);
    })
  };

  type TronAddress = {
    base58 : Text;
    evm20 : [Nat8];
  };

  func tron_address_from_sec1_public_key(public_key : [Nat8]) : Error.WalletResult<TronAddress> {
    let evm20 = switch (Addressing.evm20_from_sec1_public_key(public_key)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let payload21 = Array.append<Nat8>([TRON_PREFIX], evm20);
    #Ok({
      base58 = tron_base58check_encode(payload21);
      evm20;
    })
  };

  func tron_create_trx_transfer(
    from : TronAddress,
    to : TronAddress,
    amount_sun : Nat,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let body =
      "{" #
      "\"owner_address\":\"" # json_escape(from.base58) # "\"," #
      "\"to_address\":\"" # json_escape(to.base58) # "\"," #
      "\"amount\":" # Nat.toText(amount_sun) # "," #
      "\"visible\":true" #
      "}";
    let tx = switch (await tron_post_json("wallet/createtransaction", body, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (ensure_tron_tx_build_ok(tx, "createtransaction")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    #Ok(tx)
  };

  func tron_create_trc20_transfer(
    from : TronAddress,
    to : TronAddress,
    token : TronAddress,
    amount_units : Nat,
    memo : ?Text,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let amountWordHex = switch (abi_u256_word_hex(amount_units)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let parameterHex = tron_abi_encode_address_param(to.evm20) # amountWordHex;
    let memoPart = switch (memo) {
      case (?m0) {
        let m = Text.trim(m0, #char ' ');
        if (Text.size(m) == 0) {
          ""
        } else {
          ",\"data\":\"" # Addressing.hex_encode(Blob.toArray(Text.encodeUtf8(m))) # "\""
        }
      };
      case null "";
    };
    let body =
      "{" #
      "\"owner_address\":\"" # json_escape(from.base58) # "\"," #
      "\"contract_address\":\"" # json_escape(token.base58) # "\"," #
      "\"function_selector\":\"transfer(address,uint256)\"," #
      "\"parameter\":\"" # parameterHex # "\"," #
      "\"fee_limit\":" # Nat.toText(TRON_FEE_LIMIT_SUN_DEFAULT) # "," #
      "\"call_value\":0" #
      memoPart #
      ",\"visible\":true" #
      "}";
    let resp = switch (await tron_post_json("wallet/triggersmartcontract", body, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let resultObj = switch (json_object_field(resp, "result")) {
      case (?v) v;
      case null return #Err(#Internal("TRON triggersmartcontract missing result"));
    };
    let resultOk = switch (json_bool_field(resultObj, "result")) {
      case (?b) b;
      case null false;
    };
    if (not resultOk) {
      let msg = switch (json_string_field(resultObj, "message")) {
        case (?m) decode_hex_or_passthrough(m);
        case null truncate_text(JsonAst.show(resp), 300);
      };
      return #Err(#Internal("TRON triggersmartcontract rejected: " # msg));
    };
    let tx = switch (json_object_field(resp, "transaction")) {
      case (?v) v;
      case null return #Err(#Internal("TRON triggersmartcontract missing transaction"));
    };
    switch (ensure_tron_tx_build_ok(tx, "triggersmartcontract.transaction")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    #Ok(tx)
  };

  func ensure_tron_tx_build_ok(tx : JsonAst.JSON, txLabel : Text) : Error.WalletResult<()> {
    if (json_string_field(tx, "raw_data_hex") == null) {
      return #Err(#Internal("TRON " # txLabel # " missing raw_data_hex"));
    };
    if (json_string_field(tx, "txID") == null) {
      return #Err(#Internal("TRON " # txLabel # " missing txID"));
    };
    #Ok(())
  };

  func sign_tron_txid(txid32 : [Nat8], public_key_sec1 : [Nat8]) : async Error.WalletResult<Text> {
    if (txid32.size() != 32) return #Err(#Internal("TRON txID must be 32 bytes"));
    let sig64 = switch (await Addressing.sign_ecdsa_secp256k1_prehash32(txid32)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let recid = switch (Addressing.ecdsa_recovery_id_secp256k1_prehash32(txid32, sig64, public_key_sec1)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok(Addressing.hex_encode(Array.append<Nat8>(sig64, [recid])))
  };

  func abi_u256_word_hex(n : Nat) : Error.WalletResult<Text> {
    switch (nat_to_fixed_32_256(n)) {
      case (#Err(err)) #Err(err);
      case (#Ok(bytes)) #Ok(Addressing.hex_encode(bytes));
    }
  };

  func nat_to_fixed_32_256(n0 : Nat) : Error.WalletResult<[Nat8]> {
    let maxPlusOne : Nat = 0x1_0000000000000000000000000000000000000000000000000000000000000000;
    if (n0 >= maxPlusOne) {
      #Err(#InvalidInput("amount is too large"))
    } else {
      let out = Array.init<Nat8>(32, 0);
      var n = n0;
      var i : Nat = 32;
      while (i > 0) {
        i -= 1;
        out[i] := Nat8.fromNat(n % 256);
        n /= 256;
      };
      #Ok(Array.freeze(out))
    }
  };

  func sha256_once(bytes : [Nat8]) : [Nat8] {
    Blob.toArray(Sha256.fromArray(#sha256, bytes))
  };

  func double_sha256(bytes : [Nat8]) : [Nat8] {
    sha256_once(sha256_once(bytes))
  };

  func slice_bytes(bytes : [Nat8], start : Nat, end_exclusive : Nat) : [Nat8] {
    if (start >= end_exclusive or start >= bytes.size()) {
      return [];
    };
    let stop = if (end_exclusive <= bytes.size()) end_exclusive else bytes.size();
    let out = Buffer.Buffer<Nat8>(stop - start);
    var i = start;
    while (i < stop) {
      out.add(bytes[i]);
      i += 1;
    };
    Buffer.toArray(out)
  };

  func json_object_field(value : JsonAst.JSON, key : Text) : ?JsonAst.JSON {
    switch (value) {
      case (#Object(fields)) {
        for ((k, v) in fields.vals()) {
          if (k == key) {
            return ?v;
          };
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

  func json_bool_field(value : JsonAst.JSON, key : Text) : ?Bool {
    switch (json_object_field(value, key)) {
      case (?#Boolean(b)) ?b;
      case (_) null;
    }
  };

  func json_object_set(
    value : JsonAst.JSON,
    key : Text,
    next : JsonAst.JSON,
  ) : Error.WalletResult<JsonAst.JSON> {
    switch (value) {
      case (#Object(fields)) {
        let out = Buffer.Buffer<(Text, JsonAst.JSON)>(fields.size() + 1);
        var replaced = false;
        for ((k, v) in fields.vals()) {
          if (k == key) {
            if (not replaced) {
              out.add((k, next));
              replaced := true;
            };
          } else {
            out.add((k, v));
          };
        };
        if (not replaced) out.add((key, next));
        #Ok(#Object(Buffer.toArray(out)))
      };
      case (_) #Err(#Internal("TRON transaction payload must be a JSON object"));
    }
  };

  func json_array_first_string(value : JsonAst.JSON) : ?Text {
    switch (value) {
      case (#Array(items)) {
        if (items.size() == 0) return null;
        switch (items[0]) {
          case (#String(s)) ?s;
          case (_) null;
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
      let n = c;
      if (n < '0' or n > '9') return null;
      acc := acc * 10 + Nat8.toNat(char_digit_to_nat8(n));
    };
    ?acc
  };

  func hex_digit_value_u8(c : Char) : ?Nat8 {
    switch (hex_digit_value_char(c)) {
      case (?v) ?Nat8.fromNat(v);
      case null null;
    }
  };

  func hex_digit_value_char(c : Char) : ?Nat {
    let n = Char.toNat32(c);
    if (n >= 48 and n <= 57) return ?Nat32.toNat(n - 48);
    if (n >= 65 and n <= 70) return ?Nat32.toNat(n - 55);
    if (n >= 97 and n <= 102) return ?Nat32.toNat(n - 87);
    null
  };

  func decode_hex(input : Text) : Error.WalletResult<[Nat8]> {
    let s0 = Text.trim(input, #char ' ');
    let s = switch (Text.stripStart(s0, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(s0, #text "0X")) {
        case (?v2) v2;
        case null s0;
      };
    };
    if (Text.size(s) == 0) return #Ok([]);
    if ((Text.size(s) % 2) != 0) return #Err(#InvalidInput("hex length must be even"));
    let chars = Buffer.Buffer<Char>(Text.size(s));
    for (c in s.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    let out = Buffer.Buffer<Nat8>(arr.size() / 2);
    var i : Nat = 0;
    while (i < arr.size()) {
      let hi = switch (hex_digit_value_u8(arr[i])) {
        case (?v) v;
        case null return #Err(#InvalidInput("invalid hex character"));
      };
      let lo = switch (hex_digit_value_u8(arr[i + 1])) {
        case (?v) v;
        case null return #Err(#InvalidInput("invalid hex character"));
      };
      out.add(Nat8.fromNat((Nat8.toNat(hi) * 16) + Nat8.toNat(lo)));
      i += 2;
    };
    #Ok(Buffer.toArray(out))
  };

  func bytes_to_nat(bytes : [Nat8]) : Nat {
    var acc : Nat = 0;
    for (b in bytes.vals()) {
      acc := (acc * 256) + Nat8.toNat(b);
    };
    acc
  };

  func nat_to_bytes_be(n0 : Nat) : [Nat8] {
    if (n0 == 0) return [];
    let buf = Buffer.Buffer<Nat8>(32);
    var n = n0;
    while (n > 0) {
      buf.add(Nat8.fromNat(n % 256));
      n /= 256;
    };
    Array.reverse(Buffer.toArray(buf))
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

    let decoded = nat_to_bytes_be(acc);
    if (zeros == 0) return #Ok(decoded);
    #Ok(Array.append(Array.tabulate<Nat8>(zeros, func(_ : Nat) : Nat8 = 0), decoded))
  };

  func base58_index(alphabet : Text, c : Char) : ?Nat {
    var i : Nat = 0;
    for (x in alphabet.chars()) {
      if (x == c) return ?i;
      i += 1;
    };
    null
  };

  func parse_tron_address(value0 : Text) : Error.WalletResult<TronAddress> {
    let value = Text.trim(value0, #char ' ');
    if (Text.size(value) == 0) return #Err(#InvalidInput("TRON address is required"));

    let first = first_char(value);
    if (first == ?'T') {
      switch (tron_base58check_decode(value)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(payload)) return tron_address_from_payload(payload);
      };
    };

    let bytes = switch (decode_hex(value)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (bytes.size() == 21) {
      return tron_address_from_payload(bytes);
    };
    if (bytes.size() == 20) {
      return tron_address_from_payload(Array.append([TRON_PREFIX], bytes));
    };
    #Err(#InvalidInput("TRON address must be base58check or 20/21-byte hex"))
  };

  func first_char(t : Text) : ?Char {
    for (c in t.chars()) return ?c;
    null
  };

  func tron_address_from_payload(payload : [Nat8]) : Error.WalletResult<TronAddress> {
    if (payload.size() != 21) return #Err(#InvalidInput("TRON address payload length invalid"));
    if (payload[0] != TRON_PREFIX) {
      return #Err(#InvalidInput("TRON address hex payload must start with 0x41"));
    };
    let evm20 = slice_bytes(payload, 1, 21);
    #Ok({
      base58 = tron_base58check_encode(payload);
      evm20;
    })
  };

  func tron_base58check_encode(payload21 : [Nat8]) : Text {
    let checksum = slice_bytes(double_sha256(payload21), 0, 4);
    Addressing.base58_encode(Array.append(payload21, checksum))
  };

  func tron_base58check_decode(s : Text) : Error.WalletResult<[Nat8]> {
    let raw = switch (base58_decode(s)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (raw.size() != 25) return #Err(#InvalidInput("TRON base58check address length invalid"));
    let payload = slice_bytes(raw, 0, 21);
    let checksum = slice_bytes(raw, 21, 25);
    let expected = slice_bytes(double_sha256(payload), 0, 4);
    if (checksum != expected) return #Err(#InvalidInput("TRON address checksum mismatch"));
    #Ok(payload)
  };

  func tron_abi_encode_address_param(addr20 : [Nat8]) : Text {
    let prefix = Array.tabulate<Nat8>(12, func(_ : Nat) : Nat8 = 0);
    Addressing.hex_encode(Array.append(prefix, addr20))
  };

  func fetch_trc20_balance_raw(owner : TronAddress, token : TronAddress, rpcOverride : ?Text) : async Error.WalletResult<Nat> {
    let paramHex = tron_abi_encode_address_param(owner.evm20);
    let resp = switch (await tron_post_json(
      "wallet/triggerconstantcontract",
      "{\"owner_address\":\"" # json_escape(owner.base58) # "\"," #
      "\"contract_address\":\"" # json_escape(token.base58) # "\"," #
      "\"function_selector\":\"balanceOf(address)\"," #
      "\"parameter\":\"" # paramHex # "\"," #
      "\"visible\":true}",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    tron_constant_result_uint(resp)
  };

  func fetch_trc20_decimals(owner : TronAddress, token : TronAddress, rpcOverride : ?Text) : async Error.WalletResult<Nat8> {
    let resp = switch (await tron_post_json(
      "wallet/triggerconstantcontract",
      "{\"owner_address\":\"" # json_escape(owner.base58) # "\"," #
      "\"contract_address\":\"" # json_escape(token.base58) # "\"," #
      "\"function_selector\":\"decimals()\"," #
      "\"visible\":true}",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let n = switch (tron_constant_result_uint(resp)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (n > 255) return #Err(#Internal("TRC20 decimals out of range"));
    #Ok(Nat8.fromNat(n))
  };

  func fetch_trc20_string_property(
    owner : TronAddress,
    token : TronAddress,
    selector : Text,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<Text> {
    let resp = switch (await tron_post_json(
      "wallet/triggerconstantcontract",
      "{\"owner_address\":\"" # json_escape(owner.base58) # "\"," #
      "\"contract_address\":\"" # json_escape(token.base58) # "\"," #
      "\"function_selector\":\"" # json_escape(selector) # "\"," #
      "\"visible\":true}",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let bytes = switch (tron_constant_result_bytes(resp)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    decode_abi_string_or_bytes32(bytes)
  };

  func tron_constant_result_uint(resp : JsonAst.JSON) : Error.WalletResult<Nat> {
    switch (json_object_field(resp, "result")) {
      case (?#Object(_)) {
        switch (json_object_field(switch (json_object_field(resp, "result")) { case (?v) v; case null resp }, "message")) {
          case (?#String(msgHex)) {
            let decoded = decode_hex_or_passthrough(msgHex);
            if (Text.size(decoded) > 0) {
              return #Err(#Internal("TRON constant call error: " # decoded));
            };
          };
          case (_) {};
        };
      };
      case (_) {};
    };

    let constantHex = switch (json_object_field(resp, "constant_result")) {
      case (?v) {
        switch (json_array_first_string(v)) {
          case (?s) s;
          case null return #Err(#Internal("TRON constant call missing constant_result"));
        }
      };
      case null return #Err(#Internal("TRON constant call missing constant_result"));
    };
    let bytes = switch (decode_hex(constantHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok(bytes_to_nat(bytes))
  };

  func tron_constant_result_bytes(resp : JsonAst.JSON) : Error.WalletResult<[Nat8]> {
    switch (json_object_field(resp, "result")) {
      case (?#Object(_)) {
        switch (json_object_field(switch (json_object_field(resp, "result")) { case (?v) v; case null resp }, "message")) {
          case (?#String(msgHex)) {
            let decoded = decode_hex_or_passthrough(msgHex);
            if (Text.size(decoded) > 0) {
              return #Err(#Internal("TRON constant call error: " # decoded));
            };
          };
          case (_) {};
        };
      };
      case (_) {};
    };
    let constantHex = switch (json_object_field(resp, "constant_result")) {
      case (?v) {
        switch (json_array_first_string(v)) {
          case (?s) s;
          case null return #Err(#Internal("TRON constant call missing constant_result"));
        }
      };
      case null return #Err(#Internal("TRON constant call missing constant_result"));
    };
    decode_hex(constantHex)
  };

  func decode_abi_string_or_bytes32(bytes : [Nat8]) : Error.WalletResult<Text> {
    if (bytes.size() == 0) {
      return #Err(#Internal("TRC20 string property returned empty data"));
    };
    if (bytes.size() == 32) {
      var end = bytes.size();
      var i : Nat = 0;
      while (i < bytes.size()) {
        if (bytes[i] == 0) { end := i; i := bytes.size() } else { i += 1 };
      };
      let raw = slice_bytes(bytes, 0, end);
      switch (Text.decodeUtf8(Blob.fromArray(raw))) {
        case (?t) #Ok(Text.trim(t, #char ' '));
        case null #Err(#Internal("TRC20 bytes32 property is not utf8"));
      }
    } else if (bytes.size() >= 96) {
      let offset = switch (abi_u256_to_nat(slice_bytes(bytes, 0, 32))) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      if (offset + 64 > bytes.size()) {
        return #Err(#Internal("TRC20 ABI string offset out of range"));
      };
      let len = switch (abi_u256_to_nat(slice_bytes(bytes, offset, offset + 32))) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      let start = offset + 32;
      let end = start + len;
      if (end > bytes.size()) {
        return #Err(#Internal("TRC20 ABI string length out of range"));
      };
      let raw = slice_bytes(bytes, start, end);
      switch (Text.decodeUtf8(Blob.fromArray(raw))) {
        case (?t) #Ok(Text.trim(t, #char ' '));
        case null #Err(#Internal("TRC20 string property is not utf8"));
      }
    } else {
      #Err(#Internal("unsupported TRC20 string property ABI encoding"))
    }
  };

  func abi_u256_to_nat(word32 : [Nat8]) : Error.WalletResult<Nat> {
    if (word32.size() != 32) return #Err(#Internal("ABI word must be 32 bytes"));
    // Keep within 64-bit-ish practical bounds for array offsets/lengths.
    var i : Nat = 0;
    while (i < 24) {
      if (word32[i] != 0) return #Err(#Internal("ABI value too large"));
      i += 1;
    };
    #Ok(bytes_to_nat(word32))
  };

  func tron_post_json(path : Text, bodyText : Text, rpcOverride : ?Text) : async Error.WalletResult<JsonAst.JSON> {
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("trx rpc url resolution failed: " # msg));
    };
    let httpRes = switch (await Outcall.post_json(
      rpcUrl # "/" # path,
      Text.encodeUtf8(bodyText),
      512 * 1024 : Nat64,
      "trx rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("trx rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("trx rpc response is not utf-8"));
    };
    switch (JsonAst.parse(payloadText)) {
      case (?v) #Ok(v);
      case null #Err(#Internal("parse trx rpc response failed"));
    }
  };

  func decode_hex_or_passthrough(value : Text) : Text {
    switch (decode_hex(value)) {
      case (#Ok(bytes)) {
        if (bytes.size() == 0) return value;
        switch (Text.decodeUtf8(Blob.fromArray(bytes))) {
          case (?t) t;
          case null value;
        }
      };
      case (#Err(_)) value;
    }
  };

  func short_suffix(value : Text) : Text {
    let chars = Buffer.Buffer<Char>(Text.size(value));
    for (c in value.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    let keep : Nat = 6;
    let start = if (arr.size() > keep) arr.size() - keep else 0;
    var out = "";
    var i = start;
    while (i < arr.size()) {
      let c = arr[i];
      let n = Char.toNat32(c);
      if (n >= 97 and n <= 122) {
        out #= Text.fromChar(Char.fromNat32(n - 32));
      } else {
        out #= Text.fromChar(c);
      };
      i += 1;
    };
    out
  };

  func char_digit_to_nat8(c : Char) : Nat8 {
    Nat8.fromNat(
      Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'))
    )
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
        acc := (acc * 10) + Nat8.toNat(char_digit_to_nat8(c));
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

  func format_units(amount : Nat, decimals : Nat) : Text {
    if (decimals == 0) {
      return Nat.toText(amount);
    };
    let base = pow10(decimals);
    let whole = amount / base;
    let frac = amount % base;
    if (frac == 0) {
      return Nat.toText(whole);
    };
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
    while (end > 0 and arr[end - 1] == '0') {
      end -= 1;
    };
    if (end == 0) {
      return "0";
    };
    var out = "";
    var i : Nat = 0;
    while (i < end) {
      out #= Text.fromChar(arr[i]);
      i += 1;
    };
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
      if (i >= maxChars) { return out };
      out #= Text.fromChar(c);
      i += 1;
    };
    out
  };
}

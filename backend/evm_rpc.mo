import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Addressing "./addressing";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import EvmTx "./sdk/evm_tx";
import Types "./types";

module {
  let EVM_NATIVE_DECIMALS : Nat8 = 18;
  let EVM_NATIVE_GAS_LIMIT : Nat = 21_000;
  let EVM_ERC20_GAS_LIMIT_DEFAULT : Nat = 120_000;
  let EVM_PRIORITY_FEE_FALLBACK_WEI : Nat = 1_500_000_000;
  let ERC20_DECIMALS_SELECTOR : Text = "313ce567";
  let ERC20_SYMBOL_SELECTOR : Text = "95d89b41";
  let ERC20_NAME_SELECTOR : Text = "06fdde03";

  public func get_native_balance(
    network : Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    await get_native_balance_with_rpc(network, null, req)
  };

  public func get_native_balance_with_rpc(
    network : Text,
    rpcOverride : ?Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    let account = switch (normalize_hex_address(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (req.token) {
      case (?token) {
        if (Text.size(Text.trim(token, #char ' ')) > 0) {
          return #Err(#InvalidInput("native EVM balance does not accept token parameter"));
        };
      };
      case null {};
    };

    let resultHex = switch (await rpc_call_hex_string_with_rpc(network, rpcOverride, "eth_getBalance", "[\"" # account # "\",\"latest\"]")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let wei = switch (EvmTx.parse_hex_quantity(resultHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    #Ok({
      network;
      account;
      token = null;
      amount = ?EvmTx.format_units(wei, Nat8.toNat(EVM_NATIVE_DECIMALS));
      decimals = ?EVM_NATIVE_DECIMALS;
      block_ref = ?"latest";
      pending = false;
      message = ?"RPC eth_getBalance (formatted ETH)";
    })
  };

  public func get_erc20_balance(
    network : Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    await get_erc20_balance_with_rpc(network, null, req)
  };

  public func get_erc20_balance_with_rpc(
    network : Text,
    rpcOverride : ?Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    let account = switch (normalize_hex_address(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let tokenContract = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) {
          return #Err(#InvalidInput("token is required for ERC20 balance query"));
        };
        switch (normalize_hex_address(trimmed)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
      case null return #Err(#InvalidInput("token is required for ERC20 balance query"));
    };

    let account20 = switch (hex_address_to_20_bytes(account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_erc20_decimals(network, rpcOverride, tokenContract)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let balanceOfCall = switch (EvmTx.encode_erc20_balance_of_call(account20)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let dataHex = "0x" # Addressing.hex_encode(balanceOfCall);
    let resultHex = switch (await rpc_call_hex_string_with_rpc(
      network,
      rpcOverride,
      "eth_call",
      "[{\"to\":\"" # tokenContract # "\",\"data\":\"" # dataHex # "\"},\"latest\"]"
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let raw = switch (EvmTx.parse_hex_data(resultHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let amount = bytes_to_nat(raw);

    #Ok({
      network;
      account;
      token = ?tokenContract;
      amount = ?EvmTx.format_units(amount, Nat8.toNat(decimals));
      decimals = ?decimals;
      block_ref = ?"latest";
      pending = false;
      message = ?"RPC eth_call balanceOf(address)";
    })
  };

  public func transfer_native(
    network : Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_native_with_rpc(network, null, req)
  };

  public func transfer_native_with_rpc(
    network : Text,
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (req.token) {
      case (?token) {
        if (Text.size(Text.trim(token, #char ' ')) > 0) {
          return #Err(#InvalidInput("native EVM transfer does not accept token parameter"));
        };
      };
      case null {};
    };
    let to = switch (normalize_hex_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let valueWei = switch (EvmTx.parse_decimal_units(req.amount, Nat8.toNat(EVM_NATIVE_DECIMALS))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (valueWei == 0) return #Err(#InvalidInput("amount must be > 0"));
    let toBytes = switch (hex_address_to_20_bytes(to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let txId = switch (await send_legacy_transaction(network, rpcOverride, req.from, toBytes, valueWei, [], EVM_NATIVE_GAS_LIMIT)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok({
      network;
      accepted = true;
      tx_id = ?txId;
      message = "broadcasted raw transaction via eth_sendRawTransaction: " # txId;
    })
  };

  public func transfer_erc20(
    network : Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_erc20_with_rpc(network, null, req)
  };

  public func transfer_erc20_with_rpc(
    network : Text,
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    let tokenContract = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) return #Err(#InvalidInput("token is required for ERC20 transfer"));
        switch (normalize_hex_address(trimmed)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        }
      };
      case null return #Err(#InvalidInput("token is required for ERC20 transfer"));
    };
    let tokenContractBytes = switch (hex_address_to_20_bytes(tokenContract)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let to = switch (normalize_hex_address(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let toBytes = switch (hex_address_to_20_bytes(to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_erc20_decimals(network, rpcOverride, tokenContract)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let amountUnits = switch (EvmTx.parse_decimal_units(req.amount, Nat8.toNat(decimals))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountUnits == 0) return #Err(#InvalidInput("amount must be > 0"));
    let data = switch (EvmTx.encode_erc20_transfer_call(toBytes, amountUnits)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let txId = switch (await send_legacy_transaction(network, rpcOverride, req.from, tokenContractBytes, 0, data, EVM_ERC20_GAS_LIMIT_DEFAULT)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok({
      network;
      accepted = true;
      tx_id = ?txId;
      message = "broadcasted ERC20 transfer via eth_sendRawTransaction: " # txId;
    })
  };

  public func discover_erc20_token(
    network : Text,
    token_address : Text,
  ) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let tokenContract = switch (normalize_hex_address(token_address)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_erc20_decimals(network, null, tokenContract)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let symbol = switch (await fetch_erc20_text_field(network, null, tokenContract, ERC20_SYMBOL_SELECTOR, "symbol")) {
      case (#Ok(v)) if (Text.size(v) > 0) v else "TOKEN";
      case (#Err(_)) "TOKEN";
    };
    let name = switch (await fetch_erc20_text_field(network, null, tokenContract, ERC20_NAME_SELECTOR, "name")) {
      case (#Ok(v)) if (Text.size(v) > 0) v else symbol;
      case (#Err(_)) symbol;
    };

    #Ok({
      network;
      symbol;
      name;
      token_address = tokenContract;
      decimals = Nat8.toNat(decimals);
    })
  };

  func send_legacy_transaction(
    network : Text,
    rpcOverride : ?Text,
    fromOverride : ?Text,
    to20 : [Nat8],
    value : Nat,
    data : [Nat8],
    gasLimit : Nat,
  ) : async Error.WalletResult<Text> {
    if (to20.size() != 20) return #Err(#InvalidInput("EVM to address must be 20 bytes"));
    let publicKeyBytes = switch (await Addressing.fetch_ecdsa_secp256k1_public_key()) {
      case (#Err(err)) return #Err(err);
      case (#Ok((pub, _))) pub;
    };
    let fromAddress = switch (evm_address_from_sec1_public_key(publicKeyBytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (fromOverride) {
      case (?fromText0) {
        let fromTrimmed = Text.trim(fromText0, #char ' ');
        if (Text.size(fromTrimmed) > 0) {
          let normalizedFrom = switch (normalize_hex_address(fromTrimmed)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          if (normalizedFrom != fromAddress) {
            return #Err(#InvalidInput("from does not match canister-managed EVM address"));
          };
        };
      };
      case null {};
    };

    let chainId = switch (RpcConfig.chain_id(network)) {
      case (?n) n;
      case null return #Err(#Internal("missing chain_id config for network: " # network));
    };
    let nonce = switch (EvmTx.parse_hex_quantity(switch (await rpc_call_hex_string_with_rpc(network, rpcOverride, "eth_getTransactionCount", "[\"" # fromAddress # "\",\"pending\"]")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    })) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let gasPrice = switch (EvmTx.parse_hex_quantity(switch (await rpc_call_hex_string_with_rpc(network, rpcOverride, "eth_gasPrice", "[]")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    })) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    switch (await try_send_eip1559_transaction(
      network,
      rpcOverride,
      chainId,
      nonce,
      gasLimit,
      to20,
      value,
      data,
      publicKeyBytes,
      gasPrice,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(?txid)) return #Ok(txid);
      case (#Ok(null)) {};
    };

    let signingPayload = EvmTx.rlp_encode_legacy_unsigned(nonce, gasPrice, gasLimit, to20, value, data, chainId);
    let signingHash = EvmTx.keccak256(signingPayload);
    if (signingHash.size() != 32) return #Err(#Internal("unexpected keccak256 digest length"));
    let sig64 = switch (await Addressing.sign_ecdsa_secp256k1_prehash32(signingHash)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let recid = switch (Addressing.ecdsa_recovery_id_secp256k1_prehash32(signingHash, sig64, publicKeyBytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (Nat8.toNat(recid) >= 2) {
      return #Err(#Internal("unsupported ECDSA recovery id (x_reduced=true) for Ethereum encoding"));
    };
    let v = chainId * 2 + 35 + Nat8.toNat(recid);
    let r = bytes_to_nat(slice(sig64, 0, 32));
    let s = bytes_to_nat(slice(sig64, 32, 64));
    let signedRaw = EvmTx.rlp_encode_legacy_signed(nonce, gasPrice, gasLimit, to20, value, data, v, r, s);
    await broadcast_raw_transaction(network, rpcOverride, signedRaw)
  };

  func try_send_eip1559_transaction(
    network : Text,
    rpcOverride : ?Text,
    chainId : Nat,
    nonce : Nat,
    gasLimit : Nat,
    to20 : [Nat8],
    value : Nat,
    data : [Nat8],
    publicKeyBytes : [Nat8],
    gasPriceFallback : Nat,
  ) : async Error.WalletResult<?Text> {
    let feeParams = switch (await discover_eip1559_fee_params(network, rpcOverride, gasPriceFallback)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (feeParams) {
      case null return #Ok(null);
      case (?fees) {
        let signingPayload = EvmTx.rlp_encode_eip1559_unsigned(
          chainId,
          nonce,
          fees.max_priority_fee_per_gas,
          fees.max_fee_per_gas,
          gasLimit,
          to20,
          value,
          data,
        );
        let signingHash = EvmTx.keccak256(signingPayload);
        if (signingHash.size() != 32) return #Err(#Internal("unexpected keccak256 digest length"));
        let sig64 = switch (await Addressing.sign_ecdsa_secp256k1_prehash32(signingHash)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let recid = switch (Addressing.ecdsa_recovery_id_secp256k1_prehash32(signingHash, sig64, publicKeyBytes)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        if (Nat8.toNat(recid) >= 2) {
          return #Err(#Internal("unsupported ECDSA recovery id (x_reduced=true) for EIP-1559 encoding"));
        };
        let r = bytes_to_nat(slice(sig64, 0, 32));
        let s = bytes_to_nat(slice(sig64, 32, 64));
        let signedRaw = EvmTx.rlp_encode_eip1559_signed(
          chainId,
          nonce,
          fees.max_priority_fee_per_gas,
          fees.max_fee_per_gas,
          gasLimit,
          to20,
          value,
          data,
          recid,
          r,
          s,
        );
        let txid = switch (await broadcast_raw_transaction(network, rpcOverride, signedRaw)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        #Ok(?txid)
      }
    }
  };

  func discover_eip1559_fee_params(
    network : Text,
    rpcOverride : ?Text,
    gasPriceFallback : Nat,
  ) : async Error.WalletResult<?{
    max_priority_fee_per_gas : Nat;
    max_fee_per_gas : Nat;
  }> {
    // If the chain or RPC doesn't expose `baseFeePerGas`, we fall back to legacy.
    let latestBlock = switch (await rpc_call_with_rpc(network, rpcOverride, "eth_getBlockByNumber", "[\"latest\",false]")) {
      case (#Err(_)) return #Ok(null);
      case (#Ok(v)) v;
    };
    let baseFee = switch (json_object_field(latestBlock, "baseFeePerGas")) {
      case (?#String(s)) {
        switch (EvmTx.parse_hex_quantity(s)) {
          case (#Ok(v)) v;
          case (#Err(_)) return #Ok(null);
        }
      };
      case (_) return #Ok(null);
    };

    let priorityCandidate = switch (await rpc_call_hex_string_with_rpc(network, rpcOverride, "eth_maxPriorityFeePerGas", "[]")) {
      case (#Ok(hex)) {
        switch (EvmTx.parse_hex_quantity(hex)) {
          case (#Ok(v)) v;
          case (#Err(_)) gasPriceFallback;
        }
      };
      case (#Err(_)) gasPriceFallback;
    };
    let maxPriority = if (priorityCandidate > 0) priorityCandidate else if (gasPriceFallback > 0) gasPriceFallback else EVM_PRIORITY_FEE_FALLBACK_WEI;
    let maxFee = (baseFee * 2) + maxPriority;

    #Ok(?{
      max_priority_fee_per_gas = maxPriority;
      max_fee_per_gas = maxFee;
    })
  };

  func broadcast_raw_transaction(network : Text, rpcOverride : ?Text, rawTx : [Nat8]) : async Error.WalletResult<Text> {
    let rawTxHex = "0x" # Addressing.hex_encode(rawTx);
    switch (await rpc_call_hex_string_with_rpc(network, rpcOverride, "eth_sendRawTransaction", "[\"" # rawTxHex # "\"]")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(txid)) #Ok(txid);
    }
  };

  func evm_address_from_sec1_public_key(public_key : [Nat8]) : Error.WalletResult<Text> {
    let evm20 = switch (Addressing.evm20_from_sec1_public_key(public_key)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok("0x" # Addressing.hex_encode(evm20))
  };

  func fetch_erc20_decimals(network : Text, rpcOverride : ?Text, tokenContract : Text) : async Error.WalletResult<Nat8> {
    let resultHex = switch (await rpc_call_hex_string_with_rpc(
      network,
      rpcOverride,
      "eth_call",
      "[{\"to\":\"" # tokenContract # "\",\"data\":\"0x" # ERC20_DECIMALS_SELECTOR # "\"},\"latest\"]"
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let bytes = switch (EvmTx.parse_hex_data(resultHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (bytes.size() == 0) {
      return #Err(#Internal("ERC20 decimals() returned empty data"));
    };
    let n = bytes_to_nat(bytes);
    if (n > 255) {
      return #Err(#Internal("ERC20 decimals() value out of range"));
    };
    #Ok(Nat8.fromNat(n))
  };

  func fetch_erc20_text_field(
    network : Text,
    rpcOverride : ?Text,
    tokenContract : Text,
    selector : Text,
    methodLabel : Text,
  ) : async Error.WalletResult<Text> {
    let resultHex = switch (await rpc_call_hex_string_with_rpc(
      network,
      rpcOverride,
      "eth_call",
      "[{\"to\":\"" # tokenContract # "\",\"data\":\"0x" # selector # "\"},\"latest\"]"
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let bytes = switch (EvmTx.parse_hex_data(resultHex)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (abi_decode_string_or_bytes32(bytes)) {
      case (#Ok(v)) #Ok(v);
      case (#Err(_)) #Err(#Internal("ERC20 " # methodLabel # "() decode failed"));
    }
  };

  func abi_decode_string_or_bytes32(data : [Nat8]) : Error.WalletResult<Text> {
    if (data.size() == 0) return #Ok("");

    // Some ERC20s return bytes32 for symbol/name.
    if (data.size() == 32) {
      var end : Nat = data.size();
      while (end > 0 and data[end - 1] == 0) { end -= 1 };
      let trimmed = slice(data, 0, end);
      switch (Text.decodeUtf8(Blob.fromArray(trimmed))) {
        case (?t) #Ok(t);
        case null #Ok("0x" # Addressing.hex_encode(trimmed));
      }
    } else if (data.size() >= 64) {
      let offset = bytes_to_nat(slice(data, 0, 32));
      if (offset + 32 > data.size()) {
        return #Err(#Internal("abi string offset out of range"));
      };
      let len = bytes_to_nat(slice(data, offset, offset + 32));
      if (offset + 32 + len > data.size()) {
        return #Err(#Internal("abi string length out of range"));
      };
      let raw = slice(data, offset + 32, offset + 32 + len);
      switch (Text.decodeUtf8(Blob.fromArray(raw))) {
        case (?t) #Ok(t);
        case null #Err(#Internal("abi string is not utf8"));
      }
    } else {
      #Err(#Internal("unexpected abi string payload size"))
    }
  };

  func rpc_call_hex_string(
    network : Text,
    method : Text,
    paramsJson : Text,
  ) : async Error.WalletResult<Text> {
    await rpc_call_hex_string_with_rpc(network, null, method, paramsJson)
  };

  func rpc_call_hex_string_with_rpc(
    network : Text,
    rpcOverride : ?Text,
    method : Text,
    paramsJson : Text,
  ) : async Error.WalletResult<Text> {
    let result = switch (await rpc_call_with_rpc(network, rpcOverride, method, paramsJson)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (result) {
      case (#String(s)) #Ok(s);
      case (_) #Err(#Internal("rpc " # method # " result is not string"));
    }
  };

  func rpc_call(
    network : Text,
    method : Text,
    paramsJson : Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    await rpc_call_with_rpc(network, null, method, paramsJson)
  };

  func rpc_call_with_rpc(
    network : Text,
    rpcOverride : ?Text,
    method : Text,
    paramsJson : Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(network, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("rpc url resolution failed: " # msg));
    };
    let bodyText =
      "{\"jsonrpc\":\"2.0\",\"method\":\"" # json_escape(method) # "\",\"params\":" # paramsJson # ",\"id\":1}";
    let httpRes = switch (await Outcall.post_json(
      rpcUrl,
      Text.encodeUtf8(bodyText),
      rpc_max_response_bytes_for_method(method),
      "evm rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let body = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("parse rpc response failed: non-utf8"));
    };
    let root = switch (JsonAst.parse(body)) {
      case (?v) v;
      case null return #Err(#Internal("parse rpc response failed"));
    };
    switch (json_object_field(root, "error")) {
      case (?errObj) {
        let msg = switch (json_object_field(errObj, "message")) {
          case (?#String(s)) s;
          case (_) truncate_text(JsonAst.show(errObj), 240);
        };
        return #Err(#Internal("rpc error: " # msg));
      };
      case null {};
    };
    switch (json_object_field(root, "result")) {
      case (?v) #Ok(v);
      case null #Err(#Internal("rpc response missing result"));
    }
  };

  func normalize_hex_address(value : Text) : Error.WalletResult<Text> {
    let s = Text.trim(value, #char ' ');
    let hex = switch (Text.stripStart(s, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(s, #text "0X")) {
        case (?v2) v2;
        case null return #Err(#InvalidInput("EVM account must be a 0x-prefixed 20-byte hex address"));
      };
    };
    if (Text.size(hex) != 40) {
      return #Err(#InvalidInput("EVM account must be a 0x-prefixed 20-byte hex address"));
    };
    for (c in hex.chars()) {
      if (hex_digit(c) == null) {
        return #Err(#InvalidInput("EVM account must be a 0x-prefixed 20-byte hex address"));
      };
    };
    #Ok("0x" # to_lower_hex_text(hex))
  };

  // Lower response caps reduce required canister-http attached cycles.
  // EVM JSON-RPC responses in these methods are typically tiny.
  func rpc_max_response_bytes_for_method(method : Text) : Nat64 {
    switch (method) {
      case ("eth_chainId") 2 * 1024 : Nat64;
      case ("eth_blockNumber") 2 * 1024 : Nat64;
      case ("eth_gasPrice") 2 * 1024 : Nat64;
      case ("eth_maxPriorityFeePerGas") 2 * 1024 : Nat64;
      case ("eth_getTransactionCount") 2 * 1024 : Nat64;
      case ("eth_getBalance") 2 * 1024 : Nat64;
      case ("eth_sendRawTransaction") 4 * 1024 : Nat64;
      case ("eth_call") 8 * 1024 : Nat64;
      case ("eth_getBlockByNumber") 8 * 1024 : Nat64; // params use false (no tx objects)
      case (_) 16 * 1024 : Nat64;
    }
  };

  func hex_address_to_20_bytes(value : Text) : Error.WalletResult<[Nat8]> {
    let normalized = switch (normalize_hex_address(value)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (EvmTx.parse_hex_data(normalized)) {
      case (#Ok(bytes)) {
        if (bytes.size() == 20) #Ok(bytes) else #Err(#InvalidInput("invalid EVM hex address length"))
      };
      case (#Err(err)) #Err(err);
    }
  };


  func slice(bytes : [Nat8], start : Nat, endExclusive : Nat) : [Nat8] {
    if (start >= endExclusive or start >= bytes.size()) return [];
    let stop = if (endExclusive <= bytes.size()) endExclusive else bytes.size();
    let out = Buffer.Buffer<Nat8>(stop - start);
    var i = start;
    while (i < stop) {
      out.add(bytes[i]);
      i += 1;
    };
    Buffer.toArray(out)
  };

  func bytes_to_nat(bytes : [Nat8]) : Nat {
    var acc : Nat = 0;
    for (b in bytes.vals()) {
      acc := (acc * 256) + Nat8.toNat(b);
    };
    acc
  };

  func hex_digit(c : Char) : ?Nat {
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

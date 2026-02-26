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
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import RpcConfig "./config/rpc_config";
import SHA256 "./sha256";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.BITCOIN;
  let BTC_DECIMALS : Nat8 = 8;
  let DEFAULT_FEE_RATE_SAT_PER_VB : Nat = 5;
  let MIN_CHANGE_SATS : Nat = 330;
  let SIGHASH_DEFAULT : Nat8 = 0x00;
  let SEQUENCE_FINAL : Nat = 0xffff_ffff;
  let TX_VERSION : Nat = 2;
  let TX_LOCKTIME : Nat = 0;
  let BECH32_CONST : Nat32 = 1;
  let BECH32M_CONST : Nat32 = 0x2bc8_30a3;
  let BECH32_CHARSET : [Char] = [
    'q', 'p', 'z', 'r', 'y', '9', 'x', '8',
    'g', 'f', '2', 't', 'v', 'd', 'w', '0',
    's', '3', 'j', 'n', '5', '4', 'k', 'h',
    'c', 'e', '6', 'm', 'u', 'a', '7', 'l',
  ];

  type SchnorrKeyId = {
    algorithm : Addressing.SchnorrAlgorithm;
    name : Text;
  };

  type Bip341Aux = {
    merkle_root_hash : Blob;
  };

  type SchnorrAux = {
    #bip341 : Bip341Aux;
  };

  type SignWithSchnorrArgs = {
    message : Blob;
    derivation_path : [Blob];
    key_id : SchnorrKeyId;
    aux : ?SchnorrAux;
  };

  type SignWithSchnorrResult = {
    signature : Blob;
  };

  type WalletBtcKey = {
    address : Text;
    key_name : Text;
    internal_key_x_only : [Nat8];
    taproot_witness_program : [Nat8];
  };

  type Outpoint = {
    txid : [Nat8]; // txid order (big-endian hex decode order)
    vout : Nat;
  };

  type Utxo = {
    outpoint : Outpoint;
    value : Nat;
  };

  type TxInputTemplate = {
    utxo : Utxo;
    sequence : Nat;
  };

  type TxOutputTemplate = {
    value : Nat;
    script_pubkey : [Nat8];
  };

  type SpendPlan = {
    inputs : [TxInputTemplate];
    outputs : [TxOutputTemplate];
    fee_sats : Nat;
    fee_rate_sat_per_vb : Nat;
  };

  type DecodedSegwitAddress = {
    version : Nat8;
    program : [Nat8];
  };

  type Bech32Variant = {
    #bech32;
    #bech32m;
  };

  let Management : actor {
    sign_with_schnorr : shared (SignWithSchnorrArgs) -> async SignWithSchnorrResult;
  } = actor "aaaaa-aa";

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    let walletKey = switch (await derive_wallet_key()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    #Ok({
      network = NETWORK_NAME;
      address = walletKey.address;
      public_key_hex = Addressing.hex_encode(walletKey.internal_key_x_only);
      key_name = walletKey.key_name;
      message = ?"Derived taproot address from management canister Schnorr public key";
    })
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
    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) > 0) {
          return #Err(#InvalidInput("bitcoin_get_balance_btc does not accept token parameter"));
        };
      };
      case null {};
    };

    let payload = switch (await btc_rpc_get_json("/address/" # account, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let chainStats = switch (json_object_field(payload, "chain_stats")) {
      case (?v) v;
      case null return #Err(#Internal("btc rpc address response missing chain_stats"));
    };
    let confirmedFunded = switch (json_nat_field(chainStats, "funded_txo_sum")) {
      case (?v) v;
      case null return #Err(#Internal("btc rpc chain_stats missing funded_txo_sum"));
    };
    let confirmedSpent = switch (json_nat_field(chainStats, "spent_txo_sum")) {
      case (?v) v;
      case null return #Err(#Internal("btc rpc chain_stats missing spent_txo_sum"));
    };
    let confirmedSats = nat_saturating_sub(confirmedFunded, confirmedSpent);

    let pendingDelta : Nat = switch (json_object_field(payload, "mempool_stats")) {
      case (?mempoolStats) {
        let funded = switch (json_nat_field(mempoolStats, "funded_txo_sum")) {
          case (?v) v;
          case null 0;
        };
        let spent = switch (json_nat_field(mempoolStats, "spent_txo_sum")) {
          case (?v) v;
          case null 0;
        };
        nat_saturating_sub(funded, spent)
      };
      case null 0;
    };
    let sats = confirmedSats + pendingDelta;

    #Ok({
      network = NETWORK_NAME;
      account;
      token = null;
      amount = ?format_units(sats, Nat8.toNat(BTC_DECIMALS));
      decimals = ?BTC_DECIMALS;
      block_ref = null;
      pending = false;
      message = ?"BTC RPC address stats (confirmed + mempool delta)";
    })
  };

  public func transfer(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_with_rpc(null, req)
  };

  public func transfer_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (validate_transfer(req)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(_)) {};
    };

    switch (req.token) {
      case (?t) {
        if (Text.size(Text.trim(t, #char ' ')) > 0) {
          return #Err(#InvalidInput("bitcoin_transfer_btc does not accept token parameter"));
        };
      };
      case null {};
    };

    let walletKey = switch (await derive_wallet_key()) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    switch (req.from) {
      case (?fromRaw) {
        let from = Text.trim(fromRaw, #char ' ');
        if (Text.size(from) > 0 and Text.toLowercase(from) != Text.toLowercase(walletKey.address)) {
          return #Err(#InvalidInput("from does not match canister-managed BTC address"));
        };
      };
      case null {};
    };

    let amountSats = switch (parse_decimal_btc_to_sats(req.amount)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountSats == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };

    let toAddress = Text.toLowercase(Text.trim(req.to, #char ' '));
    let toScript = switch (script_pubkey_from_btc_address(toAddress, expected_hrp())) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let changeScript = script_pubkey_p2tr(walletKey.taproot_witness_program);
    let sourceScript = changeScript;

    let utxos = switch (await fetch_all_utxos(walletKey.address, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (utxos.size() == 0) {
      return #Err(#Internal("no BTC UTXOs available"));
    };

    let feeRate = await fetch_fee_rate_sat_per_vb(rpcOverride);
    let plan = switch (build_spend_plan(utxos, amountSats, toScript, changeScript, feeRate)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let witnessesVar = Array.init<[[Nat8]]>(plan.inputs.size(), []);
    var inputIndex : Nat = 0;
    while (inputIndex < plan.inputs.size()) {
      let sighash = switch (
        taproot_key_spend_sighash(
          TX_VERSION,
          TX_LOCKTIME,
          plan.inputs,
          plan.outputs,
          inputIndex,
          sourceScript,
        )
      ) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      let sig = switch (await sign_taproot_keypath_sighash(sighash, walletKey.key_name)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      witnessesVar[inputIndex] := [sig];
      inputIndex += 1;
    };

    let witnesses = Array.freeze(witnessesVar);
    let txBytes = serialize_tx(plan.inputs, plan.outputs, witnesses, true);
    let rawTxHex = Addressing.hex_encode(txBytes);
    let txidFromRpc = switch (await broadcast_raw_transaction(rawTxHex, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    let txid = if (Text.size(Text.trim(txidFromRpc, #char ' ')) == 0) {
      txid_hex(plan.inputs, plan.outputs, witnesses)
    } else {
      Text.trim(txidFromRpc, #char ' ')
    };

    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = ?txid;
      message =
        "btc rpc send accepted (fee=" # Nat.toText(plan.fee_sats) #
        " sats, fee_rate=" # Nat.toText(plan.fee_rate_sat_per_vb) # " sat/vB)";
    })
  };

  func derive_wallet_key() : async Error.WalletResult<WalletBtcKey> {
    let key = await Addressing.fetch_schnorr_public_key(#bip340secp256k1);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((publicKey, keyName))) {
        let internalXOnly = switch (parse_bip340_internal_key(publicKey)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let witnessProgram = switch (Addressing.taproot_output_key_xonly_from_internal_bip340(internalXOnly)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let address = switch (Addressing.encode_segwit_v1_bech32m(bitcoin_hrp(), witnessProgram)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        #Ok({
          address;
          key_name = keyName;
          internal_key_x_only = internalXOnly;
          taproot_witness_program = witnessProgram;
        })
      };
    }
  };

  func parse_bip340_internal_key(raw : [Nat8]) : Error.WalletResult<[Nat8]> {
    if (raw.size() == 32) {
      return #Ok(raw);
    };
    if (raw.size() == 33) {
      let prefix = raw[0];
      if (prefix != 0x02 and prefix != 0x03) {
        return #Err(#Internal("invalid BTC secp256k1 compressed key prefix"));
      };
      return #Ok(slice_bytes(raw, 1, 33));
    };
    #Err(#Internal("unexpected BTC public key length: " # Nat.toText(raw.size())))
  };

  func fetch_all_utxos(address : Text, rpcOverride : ?Text) : async Error.WalletResult<[Utxo]> {
    let payload = switch (await btc_rpc_get_json("/address/" # address # "/utxo", rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (payload) {
      case (#Array(rows)) {
        let out = Buffer.Buffer<Utxo>(rows.size());
        for (row in rows.vals()) {
          let txidText = switch (json_text_field(row, "txid")) {
            case (?v) v;
            case null return #Err(#Internal("btc rpc utxo missing txid"));
          };
          let txidBytes = switch (parse_txid_hex_to_bytes(txidText)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(v)) v;
          };
          let vout = switch (json_nat_field(row, "vout")) {
            case (?v) v;
            case null return #Err(#Internal("btc rpc utxo missing vout"));
          };
          let value = switch (json_nat_field(row, "value")) {
            case (?v) v;
            case null return #Err(#Internal("btc rpc utxo missing value"));
          };
          out.add({ outpoint = { txid = txidBytes; vout }; value });
        };
        #Ok(Buffer.toArray(out))
      };
      case (_) #Err(#Internal("btc rpc utxo response is not array"));
    }
  };

  func fetch_fee_rate_sat_per_vb(rpcOverride : ?Text) : async Nat {
    switch (await btc_rpc_get_json("/fee-estimates", rpcOverride)) {
      case (#Ok(fees)) {
        let candidates : [Text] = ["3", "2", "6", "1"];
        for (key in candidates.vals()) {
          switch (json_nat_field(fees, key)) {
            case (?v) {
              if (v >= 1) return v else return 1;
            };
            case null {};
          }
        }
      };
      case (#Err(_)) {};
    };
    DEFAULT_FEE_RATE_SAT_PER_VB
  };

  func build_spend_plan(
    utxos : [Utxo],
    amount_sats : Nat,
    to_script : [Nat8],
    change_script : [Nat8],
    fee_rate_sat_per_vb_0 : Nat,
  ) : Error.WalletResult<SpendPlan> {
    let feeRate = if (fee_rate_sat_per_vb_0 >= 1) fee_rate_sat_per_vb_0 else 1;
    let sorted = sort_utxos_by_value(utxos);

    let selected = Buffer.Buffer<Utxo>(sorted.size());
    var totalIn : Nat = 0;

    for (utxo in sorted.vals()) {
      totalIn += utxo.value;
      selected.add(utxo);

      let selectedArr = Buffer.toArray(selected);
      let inputs = Array.tabulate<TxInputTemplate>(
        selectedArr.size(),
        func(i : Nat) : TxInputTemplate {
          { utxo = selectedArr[i]; sequence = SEQUENCE_FINAL }
        },
      );

      let oneOutput : [TxOutputTemplate] = [{ value = amount_sats; script_pubkey = to_script }];
      let feeNoChange = estimate_signed_tx_vbytes(inputs.size(), oneOutput) * feeRate;
      let neededNoChange = amount_sats + feeNoChange;
      if (totalIn >= neededNoChange) {
        let twoOutputs : [TxOutputTemplate] = [
          { value = amount_sats; script_pubkey = to_script },
          { value = 0; script_pubkey = change_script },
        ];
        let feeWithChange = estimate_signed_tx_vbytes(inputs.size(), twoOutputs) * feeRate;
        let neededWithChange = amount_sats + feeWithChange;

        if (totalIn >= neededWithChange) {
          let change = totalIn - neededWithChange;
          if (change >= MIN_CHANGE_SATS) {
            let outputs : [TxOutputTemplate] = [
              { value = amount_sats; script_pubkey = to_script },
              { value = change; script_pubkey = change_script },
            ];
            return #Ok({
              inputs;
              outputs;
              fee_sats = feeWithChange;
              fee_rate_sat_per_vb = feeRate;
            });
          };
        };

        if (totalIn >= amount_sats + feeNoChange) {
          return #Ok({
            inputs;
            outputs = oneOutput;
            fee_sats = feeNoChange;
            fee_rate_sat_per_vb = feeRate;
          });
        };
      };
    };

    #Err(#Internal("insufficient BTC funds (including fee)"))
  };

  func sort_utxos_by_value(utxos : [Utxo]) : [Utxo] {
    let a = Array.thaw<Utxo>(utxos);
    var i : Nat = 0;
    while (i < a.size()) {
      var minIdx = i;
      var j = i + 1;
      while (j < a.size()) {
        if (a[j].value < a[minIdx].value) {
          minIdx := j;
        };
        j += 1;
      };
      if (minIdx != i) {
        let tmp = a[i];
        a[i] := a[minIdx];
        a[minIdx] := tmp;
      };
      i += 1;
    };
    Array.freeze(a)
  };

  func sign_taproot_keypath_sighash(
    sighash32 : [Nat8],
    key_name : Text,
  ) : async Error.WalletResult<[Nat8]> {
    if (sighash32.size() != 32) {
      return #Err(#Internal("BTC sighash must be 32 bytes"));
    };
    let args : SignWithSchnorrArgs = {
      message = Blob.fromArray(sighash32);
      derivation_path = [];
      key_id = {
        algorithm = #bip340secp256k1;
        name = key_name;
      };
      aux = ?(#bip341({ merkle_root_hash = Blob.fromArray([]) }));
    };
    try {
      let result = await Management.sign_with_schnorr(args);
      let sig = Blob.toArray(result.signature);
      if (sig.size() != 64) {
        return #Err(#Internal("unexpected taproot signature length: " # Nat.toText(sig.size())));
      };
      #Ok(sig)
    } catch e {
      #Err(#Internal("sign_with_schnorr failed: " # MoError.message(e)))
    }
  };

  func taproot_key_spend_sighash(
    version : Nat,
    lock_time : Nat,
    inputs : [TxInputTemplate],
    outputs : [TxOutputTemplate],
    input_index : Nat,
    source_script_pubkey : [Nat8],
  ) : Error.WalletResult<[Nat8]> {
    if (input_index >= inputs.size()) {
      return #Err(#Internal("taproot sighash input index out of range"));
    };

    let prevoutsSer = Buffer.Buffer<Nat8>(inputs.size() * 36);
    let amountsSer = Buffer.Buffer<Nat8>(inputs.size() * 8);
    let scriptpubkeysSer = Buffer.Buffer<Nat8>(inputs.size() * (source_script_pubkey.size() + 5));
    let sequencesSer = Buffer.Buffer<Nat8>(inputs.size() * 4);

    for (input in inputs.vals()) {
      serialize_outpoint_into(input.utxo, prevoutsSer);
      write_u64_le_into(input.utxo.value, amountsSer);
      write_compact_size_into(source_script_pubkey.size(), scriptpubkeysSer);
      append_bytes_into(source_script_pubkey, scriptpubkeysSer);
      write_u32_le_into(input.sequence, sequencesSer);
    };

    let outputsSer = Buffer.Buffer<Nat8>(outputs_serialized_len_estimate(outputs));
    for (output in outputs.vals()) {
      serialize_output_into(output, outputsSer);
    };

    let hashPrevouts = sha256_once(Buffer.toArray(prevoutsSer));
    let hashAmounts = sha256_once(Buffer.toArray(amountsSer));
    let hashScriptpubkeys = sha256_once(Buffer.toArray(scriptpubkeysSer));
    let hashSequences = sha256_once(Buffer.toArray(sequencesSer));
    let hashOutputs = sha256_once(Buffer.toArray(outputsSer));

    let msg = Buffer.Buffer<Nat8>(1 + 1 + 4 + 4 + 32 * 5 + 1 + 4);
    msg.add(0x00); // epoch
    msg.add(SIGHASH_DEFAULT);
    write_u32_le_into(version, msg);
    write_u32_le_into(lock_time, msg);
    append_bytes_into(hashPrevouts, msg);
    append_bytes_into(hashAmounts, msg);
    append_bytes_into(hashScriptpubkeys, msg);
    append_bytes_into(hashSequences, msg);
    append_bytes_into(hashOutputs, msg);
    msg.add(0x00); // spend_type = key path, no annex
    write_u32_le_into(input_index, msg);

    #Ok(tagged_hash_sha256("TapSighash", Buffer.toArray(msg)))
  };

  func estimate_signed_tx_vbytes(input_count : Nat, outputs : [TxOutputTemplate]) : Nat {
    let nonWitnessLen = serialized_tx_len_no_witness(input_count, outputs);
    let witnessLen = 2 + (input_count * (1 + 1 + 64)); // marker+flag + stack_count + push_len + sig(64)
    let weight = (nonWitnessLen * 4) + witnessLen;
    (weight + 3) / 4
  };

  func serialized_tx_len_no_witness(input_count : Nat, outputs : [TxOutputTemplate]) : Nat {
    4 + compact_size_len(input_count) + (input_count * 41) + compact_size_len(outputs.size()) +
    outputs_serialized_len_estimate(outputs) + 4
  };

  func outputs_serialized_len_estimate(outputs : [TxOutputTemplate]) : Nat {
    var out : Nat = 0;
    for (o in outputs.vals()) {
      out += serialized_output_len(o);
    };
    out
  };

  func serialized_output_len(output : TxOutputTemplate) : Nat {
    8 + compact_size_len(output.script_pubkey.size()) + output.script_pubkey.size()
  };

  func serialize_tx(
    inputs : [TxInputTemplate],
    outputs : [TxOutputTemplate],
    witnesses : [[[Nat8]]],
    include_witness : Bool,
  ) : [Nat8] {
    let out = Buffer.Buffer<Nat8>(256);
    write_u32_le_into(TX_VERSION, out);
    if (include_witness) {
      out.add(0x00);
      out.add(0x01);
    };
    write_compact_size_into(inputs.size(), out);
    for (input in inputs.vals()) {
      serialize_outpoint_into(input.utxo, out);
      out.add(0x00); // empty scriptSig
      write_u32_le_into(input.sequence, out);
    };
    write_compact_size_into(outputs.size(), out);
    for (output in outputs.vals()) {
      serialize_output_into(output, out);
    };
    if (include_witness) {
      var i : Nat = 0;
      while (i < inputs.size()) {
        let witness : [[Nat8]] = if (i < witnesses.size()) witnesses[i] else [];
        write_compact_size_into(witness.size(), out);
        for (item in witness.vals()) {
          write_compact_size_into(item.size(), out);
          append_bytes_into(item, out);
        };
        i += 1;
      };
    };
    write_u32_le_into(TX_LOCKTIME, out);
    Buffer.toArray(out)
  };

  func txid_hex(
    inputs : [TxInputTemplate],
    outputs : [TxOutputTemplate],
    witnesses : [[[Nat8]]],
  ) : Text {
    let legacy = serialize_tx(inputs, outputs, witnesses, false);
    Addressing.hex_encode(Array.reverse(double_sha256(legacy)))
  };

  func serialize_outpoint_into(utxo : Utxo, out : Buffer.Buffer<Nat8>) {
    let txidReversed = Array.reverse(utxo.outpoint.txid);
    append_bytes_into(txidReversed, out);
    write_u32_le_into(utxo.outpoint.vout, out);
  };

  func serialize_output_into(output : TxOutputTemplate, out : Buffer.Buffer<Nat8>) {
    write_u64_le_into(output.value, out);
    write_compact_size_into(output.script_pubkey.size(), out);
    append_bytes_into(output.script_pubkey, out);
  };

  func script_pubkey_p2tr(witness_program : [Nat8]) : [Nat8] {
    let out = Buffer.Buffer<Nat8>(2 + witness_program.size());
    out.add(0x51); // OP_1
    out.add(0x20); // push32
    append_bytes_into(witness_program, out);
    Buffer.toArray(out)
  };

  func script_pubkey_from_btc_address(address : Text, expected_hrp : Text) : Error.WalletResult<[Nat8]> {
    let decoded = switch (decode_segwit_address(address, expected_hrp)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (decoded.program.size() > 255) {
      return #Err(#InvalidInput("witness program too long"));
    };
    let script = Buffer.Buffer<Nat8>(2 + decoded.program.size());
    let version = Nat8.toNat(decoded.version);
    if (version > 16) return #Err(#InvalidInput("unsupported witness version"));
    let op : Nat8 = if (version == 0) {
      0x00
    } else {
      Nat8.fromNat(0x50 + version)
    };
    script.add(op);
    script.add(Nat8.fromNat(decoded.program.size()));
    append_bytes_into(decoded.program, script);
    #Ok(Buffer.toArray(script))
  };

  func decode_segwit_address(address : Text, expected_hrp : Text) : Error.WalletResult<DecodedSegwitAddress> {
    let addr = Text.toLowercase(Text.trim(address, #char ' '));
    if (Text.size(addr) == 0) {
      return #Err(#InvalidInput("BTC address is required"));
    };

    let chars = text_to_chars(addr);
    var sepPos : ?Nat = null;
    var i : Nat = 0;
    while (i < chars.size()) {
      if (chars[i] == '1') {
        sepPos := ?i;
      };
      i += 1;
    };
    let sep = switch (sepPos) {
      case (?v) v;
      case null return #Err(#InvalidInput("invalid bech32 address"));
    };
    if (sep == 0 or (sep + 7) > chars.size()) {
      return #Err(#InvalidInput("invalid bech32 address length"));
    };

    let hrp = chars_slice_to_text(chars, 0, sep);
    if (hrp != expected_hrp) {
      return #Err(#InvalidInput("BTC address hrp mismatch: expected " # expected_hrp # ", got " # hrp));
    };

    let data = Buffer.Buffer<Nat8>(chars.size() - sep - 1);
    i := sep + 1;
    while (i < chars.size()) {
      switch (bech32_charset_index(chars[i])) {
        case (?idx) data.add(idx);
        case null return #Err(#InvalidInput("invalid bech32 character"));
      };
      i += 1;
    };

    let dataArr = Buffer.toArray(data);
    if (dataArr.size() < 7) {
      return #Err(#InvalidInput("invalid bech32 payload"));
    };

    let checksumVariant = switch (verify_bech32_checksum(hrp, dataArr)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let payload = slice_bytes(dataArr, 0, dataArr.size() - 6);
    if (payload.size() == 0) {
      return #Err(#InvalidInput("invalid segwit payload"));
    };

    let version = payload[0];
    if (Nat8.toNat(version) > 16) {
      return #Err(#InvalidInput("unsupported witness version"));
    };
    if (version == 0 and checksumVariant != #bech32) {
      return #Err(#InvalidInput("v0 segwit address must use bech32 checksum"));
    };
    if (version != 0 and checksumVariant != #bech32m) {
      return #Err(#InvalidInput("segwit v1+ address must use bech32m checksum"));
    };

    let program = switch (convert_bits_5_to_8(slice_bytes(payload, 1, payload.size()))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (program.size() < 2 or program.size() > 40) {
      return #Err(#InvalidInput("invalid witness program length"));
    };
    if (version == 0 and not (program.size() == 20 or program.size() == 32)) {
      return #Err(#InvalidInput("v0 witness program length must be 20 or 32"));
    };

    #Ok({ version; program })
  };

  func verify_bech32_checksum(hrp : Text, data : [Nat8]) : Error.WalletResult<Bech32Variant> {
    let values = Buffer.Buffer<Nat8>(hrp.size() * 2 + 1 + data.size());
    append_bytes_into(hrp_expand(hrp), values);
    append_bytes_into(data, values);
    let polymod = bech32_polymod(Buffer.toArray(values));
    if (polymod == BECH32_CONST) {
      #Ok(#bech32)
    } else if (polymod == BECH32M_CONST) {
      #Ok(#bech32m)
    } else {
      #Err(#InvalidInput("invalid bech32 checksum"))
    }
  };

  func convert_bits_5_to_8(data : [Nat8]) : Error.WalletResult<[Nat8]> {
    var acc : Nat32 = 0;
    var bits : Nat32 = 0;
    let out = Buffer.Buffer<Nat8>(data.size());
    for (value in data.vals()) {
      if (Nat8.toNat(value) >= 32) {
        return #Err(#InvalidInput("invalid bech32 data value"));
      };
      acc := (acc << (5 : Nat32)) | Nat32.fromNat(Nat8.toNat(value));
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        out.add(Nat8.fromNat(Nat32.toNat((acc >> bits) & (0xff : Nat32))));
      };
    };
    if (bits > 0 and (((acc << (8 - bits)) & (0xff : Nat32)) != 0)) {
      return #Err(#InvalidInput("invalid bech32 padding"));
    };
    #Ok(Buffer.toArray(out))
  };

  func hrp_expand(hrp : Text) : [Nat8] {
    let bytes = Blob.toArray(Text.encodeUtf8(hrp));
    let out = Buffer.Buffer<Nat8>(bytes.size() * 2 + 1);
    for (b in bytes.vals()) {
      out.add(Nat8.fromNat(Nat8.toNat(b) / 32));
    };
    out.add(0);
    for (b in bytes.vals()) {
      out.add(Nat8.fromNat(Nat8.toNat(b) % 32));
    };
    Buffer.toArray(out)
  };

  func bech32_polymod(values : [Nat8]) : Nat32 {
    let gen : [Nat32] = [
      0x3b6a_57b2,
      0x2650_8e6d,
      0x1ea1_19fa,
      0x3d42_33dd,
      0x2a14_62b3,
    ];
    var chk : Nat32 = 1;
    for (value in values.vals()) {
      let top : Nat32 = chk >> (25 : Nat32);
      chk := ((chk & (0x01ff_ffff : Nat32)) << (5 : Nat32)) ^ Nat32.fromNat(Nat8.toNat(value));
      var i : Nat = 0;
      while (i < gen.size()) {
        if (((top >> Nat32.fromNat(i)) & (1 : Nat32)) != 0) {
          chk := chk ^ gen[i];
        };
        i += 1;
      };
    };
    chk
  };

  func bech32_charset_index(c : Char) : ?Nat8 {
    var i : Nat = 0;
    while (i < BECH32_CHARSET.size()) {
      if (BECH32_CHARSET[i] == c) {
        return ?Nat8.fromNat(i);
      };
      i += 1;
    };
    null
  };

  func parse_decimal_btc_to_sats(value : Text) : Error.WalletResult<Nat> {
    switch (parse_decimal_units_ignoring_separators(value, Nat8.toNat(BTC_DECIMALS))) {
      case (#Err(err)) #Err(err);
      case (#Ok(v)) {
        if (v == 0) #Ok(0) else #Ok(v)
      };
    }
  };

  func parse_decimal_units_ignoring_separators(value : Text, decimals : Nat) : Error.WalletResult<Nat> {
    let t = Text.trim(value, #char ' ');
    if (Text.size(t) == 0) return #Err(#InvalidInput("amount is required"));
    if (Text.startsWith(t, #char '-')) return #Err(#InvalidInput("amount must be positive"));

    var seenDot = false;
    var fracDigits : Nat = 0;
    var acc : Nat = 0;
    for (c in t.chars()) {
      if (c == '_' or c == ',') {
        // ignore numeric separators (Rust parity)
      } else if (c == '.') {
        if (seenDot) return #Err(#InvalidInput("amount format is invalid"));
        seenDot := true;
      } else {
        if (c < '0' or c > '9') return #Err(#InvalidInput("amount must be decimal"));
        acc := (acc * 10) + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
        if (seenDot) {
          fracDigits += 1;
          if (fracDigits > decimals) return #Err(#InvalidInput("too many decimal places"));
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

  func validate_transfer(req : Types.TransferRequest) : Error.WalletResult<()> {
    if (Text.size(Text.trim(req.to, #char ' ')) == 0) {
      return #Err(#InvalidInput("to is required"));
    };
    if (Text.size(Text.trim(req.amount, #char ' ')) == 0) {
      return #Err(#InvalidInput("amount is required"));
    };
    #Ok(())
  };

  func expected_hrp() : Text { bitcoin_hrp() };
  func bitcoin_hrp() : Text { "bc" };

  func broadcast_raw_transaction(raw_tx_hex : Text, rpcOverride : ?Text) : async Error.WalletResult<Text> {
    let body = Blob.fromArray(Blob.toArray(Text.encodeUtf8(Text.trim(raw_tx_hex, #char ' '))));
    await btc_rpc_post_text("/tx", body, "text/plain", rpcOverride)
  };

  func btc_rpc_get_json(path : Text, rpcOverride : ?Text) : async Error.WalletResult<JsonAst.JSON> {
    let rpcBase = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("btc rpc url resolution failed: " # msg));
    };
    let httpRes = switch (await Outcall.get_json(rpcBase # path, btc_rpc_max_response_bytes_for_path(path), "btc rpc")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("btc rpc http status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("btc rpc response is not utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("btc rpc parse response failed"));
    };
    #Ok(payload)
  };

  func btc_rpc_post_text(path : Text, body : Blob, content_type : Text, rpcOverride : ?Text) : async Error.WalletResult<Text> {
    let rpcBase = switch (RpcConfig.resolve_rpc_url(NETWORK_NAME, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("btc rpc url resolution failed: " # msg));
    };
    let httpRes = switch (await Outcall.post_text(rpcBase # path, body, content_type, "text/plain", 64 * 1024 : Nat64, "btc rpc")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let snippet = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) truncate_text(t, 240);
        case null "<non-utf8>";
      };
      return #Err(#Internal("btc rpc post status " # Nat.toText(httpRes.status) # ": " # snippet));
    };
    switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) #Ok(Text.trim(t, #char ' '));
      case null #Err(#Internal("btc rpc response is not utf8"));
    }
  };

  func btc_rpc_max_response_bytes_for_path(path : Text) : Nat64 {
    if (path == "/fee-estimates") {
      return 8 * 1024 : Nat64;
    };
    switch (Text.stripEnd(path, #text "/utxo")) {
      case (?_) {
        // UTXO lists can be larger than address summary responses.
        return 128 * 1024 : Nat64;
      };
      case null {};
    };
    switch (Text.stripStart(path, #text "/address/")) {
      case (?_) {
        // Address summary used by balance query is small.
        return 16 * 1024 : Nat64;
      };
      case null {};
    };
    64 * 1024 : Nat64
  };

  func parse_txid_hex_to_bytes(txid_hex : Text) : Error.WalletResult<[Nat8]> {
    let hex = Text.trim(txid_hex, #char ' ');
    if (Text.size(hex) != 64) {
      return #Err(#Internal("btc rpc utxo txid length invalid: " # Nat.toText(Text.size(hex))));
    };
    let chars = text_to_chars(hex);
    let out = Buffer.Buffer<Nat8>(32);
    var i : Nat = 0;
    while (i + 1 < chars.size()) {
      let hi = switch (decode_hex_nibble(chars[i])) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      let lo = switch (decode_hex_nibble(chars[i + 1])) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      out.add(Nat8.fromNat((Nat8.toNat(hi) * 16) + Nat8.toNat(lo)));
      i += 2;
    };
    #Ok(Buffer.toArray(out))
  };

  func decode_hex_nibble(c : Char) : Error.WalletResult<Nat8> {
    if (c >= '0' and c <= '9') {
      return #Ok(Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'))));
    };
    if (c >= 'a' and c <= 'f') {
      return #Ok(Nat8.fromNat(10 + Nat32.toNat(Char.toNat32(c) - Char.toNat32('a'))));
    };
    if (c >= 'A' and c <= 'F') {
      return #Ok(Nat8.fromNat(10 + Nat32.toNat(Char.toNat32(c) - Char.toNat32('A'))));
    };
    #Err(#Internal("btc rpc returned invalid hex"))
  };

  func append_bytes_into(bytes : [Nat8], out : Buffer.Buffer<Nat8>) {
    for (b in bytes.vals()) { out.add(b) };
  };

  func write_u32_le_into(n0 : Nat, out : Buffer.Buffer<Nat8>) {
    var n = n0;
    var i : Nat = 0;
    while (i < 4) {
      out.add(Nat8.fromNat(n % 256));
      n /= 256;
      i += 1;
    };
  };

  func write_u64_le_into(n0 : Nat, out : Buffer.Buffer<Nat8>) {
    var n = n0;
    var i : Nat = 0;
    while (i < 8) {
      out.add(Nat8.fromNat(n % 256));
      n /= 256;
      i += 1;
    };
  };

  func compact_size_len(n : Nat) : Nat {
    if (n <= 252) {
      1
    } else if (n <= 0xffff) {
      3
    } else if (n <= 0xffff_ffff) {
      5
    } else {
      9
    }
  };

  func write_compact_size_into(n : Nat, out : Buffer.Buffer<Nat8>) {
    if (n <= 252) {
      out.add(Nat8.fromNat(n));
    } else if (n <= 0xffff) {
      out.add(0xfd);
      var x = n;
      var i : Nat = 0;
      while (i < 2) {
        out.add(Nat8.fromNat(x % 256));
        x /= 256;
        i += 1;
      };
    } else if (n <= 0xffff_ffff) {
      out.add(0xfe);
      write_u32_le_into(n, out);
    } else {
      out.add(0xff);
      write_u64_le_into(n, out);
    }
  };

  func sha256_once(data : [Nat8]) : [Nat8] {
    Blob.toArray(SHA256.fromArray(#sha256, data))
  };

  func double_sha256(data : [Nat8]) : [Nat8] {
    let first = Blob.toArray(SHA256.fromArray(#sha256, data));
    Blob.toArray(SHA256.fromArray(#sha256, first))
  };

  func tagged_hash_sha256(tag : Text, msg : [Nat8]) : [Nat8] {
    let tagHash = sha256_once(Blob.toArray(Text.encodeUtf8(tag)));
    sha256_once(Array.append(Array.append(tagHash, tagHash), msg))
  };

  func text_to_chars(t : Text) : [Char] {
    let buf = Buffer.Buffer<Char>(Text.size(t));
    for (c in t.chars()) { buf.add(c) };
    Buffer.toArray(buf)
  };

  func chars_slice_to_text(chars : [Char], start : Nat, end_exclusive : Nat) : Text {
    if (start >= end_exclusive or start >= chars.size()) return "";
    let stop = if (end_exclusive <= chars.size()) end_exclusive else chars.size();
    var out = "";
    var i = start;
    while (i < stop) {
      out #= Text.fromChar(chars[i]);
      i += 1;
    };
    out
  };

  func nat_saturating_sub(a : Nat, b : Nat) : Nat {
    if (a >= b) a - b else 0
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

  func json_text_field(value : JsonAst.JSON, key : Text) : ?Text {
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
}

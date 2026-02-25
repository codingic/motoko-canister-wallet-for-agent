import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Error "../error";
import SHA3 "../sha3";

module {
  let ERC20_TRANSFER_SELECTOR : [Nat8] = [0xa9, 0x05, 0x9c, 0xbb];
  let ERC20_BALANCE_OF_SELECTOR : [Nat8] = [0x70, 0xa0, 0x82, 0x31];
  let MAX_U256_PLUS_ONE : Nat = 0x1_0000000000000000000000000000000000000000000000000000000000000000;

  public func encode_erc20_transfer_call(to20 : [Nat8], amount : Nat) : Error.WalletResult<[Nat8]> {
    if (to20.size() != 20) {
      return #Err(#InvalidInput("ERC20 transfer target must be 20 bytes"));
    };
    let amountWord = switch (u256_word(amount)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok(
      concat_bytes([
        ERC20_TRANSFER_SELECTOR,
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        to20,
        amountWord,
      ])
    )
  };

  public func encode_erc20_balance_of_call(account20 : [Nat8]) : Error.WalletResult<[Nat8]> {
    if (account20.size() != 20) {
      return #Err(#InvalidInput("ERC20 account must be 20 bytes"));
    };
    #Ok(
      concat_bytes([
        ERC20_BALANCE_OF_SELECTOR,
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        account20,
      ])
    )
  };

  public func parse_hex_quantity(hex : Text) : Error.WalletResult<Nat> {
    let s0 = Text.trim(hex, #char ' ');
    let s = switch (Text.stripStart(s0, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(s0, #text "0X")) {
        case (?v2) v2;
        case null return #Err(#Internal("rpc result is not a hex quantity"));
      };
    };
    if (Text.size(s) == 0) {
      return #Err(#Internal("rpc result hex quantity is empty"));
    };
    var acc : Nat = 0;
    for (c in s.chars()) {
      let d = switch (hex_digit(c)) {
        case (?v) v;
        case null return #Err(#Internal("rpc result hex quantity parse failed"));
      };
      acc := (acc * 16) + d;
    };
    #Ok(acc)
  };

  public func parse_hex_data(hex : Text) : Error.WalletResult<[Nat8]> {
    let s0 = Text.trim(hex, #char ' ');
    let s = switch (Text.stripStart(s0, #text "0x")) {
      case (?v) v;
      case null switch (Text.stripStart(s0, #text "0X")) {
        case (?v2) v2;
        case null return #Err(#Internal("rpc result is not hex data"));
      };
    };
    if (Text.size(s) == 0) return #Ok([]);
    if ((Text.size(s) % 2) != 0) return #Err(#Internal("rpc hex data length is odd"));

    let chars = chars_array(s);
    let out = Buffer.Buffer<Nat8>(chars.size() / 2);
    var i : Nat = 0;
    while (i < chars.size()) {
      let hi = switch (hex_digit(chars[i])) {
        case (?v) v;
        case null return #Err(#InvalidInput("invalid hex character"));
      };
      let lo = switch (hex_digit(chars[i + 1])) {
        case (?v) v;
        case null return #Err(#InvalidInput("invalid hex character"));
      };
      out.add(Nat8.fromNat((hi * 16) + lo));
      i += 2;
    };
    #Ok(Buffer.toArray(out))
  };

  public func parse_decimal_units(value : Text, decimals : Nat) : Error.WalletResult<Nat> {
    let t = Text.trim(value, #char ' ');
    if (Text.size(t) == 0) return #Err(#InvalidInput("amount is required"));
    if (Text.startsWith(t, #char '-')) return #Err(#InvalidInput("amount must be positive"));

    var seenDot = false;
    var fracDigits : Nat = 0;
    var acc : Nat = 0;
    for (c in t.chars()) {
      if (c == '.') {
        if (seenDot) return #Err(#InvalidInput("invalid decimal amount format"));
        seenDot := true;
      } else {
        if (c < '0' or c > '9') return #Err(#InvalidInput("amount has non-digit characters"));
        acc := (acc * 10) + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
        if (seenDot) {
          fracDigits += 1;
          if (fracDigits > decimals) {
            return #Err(#InvalidInput("amount supports at most " # Nat.toText(decimals) # " decimal places"));
          };
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

  public func format_units(value : Nat, decimals : Nat) : Text {
    if (decimals == 0) return Nat.toText(value);
    if (value == 0) return "0";
    let raw = Nat.toText(value);
    if (Text.size(raw) <= decimals) {
      let out = "0." # repeat_text("0", decimals - Text.size(raw)) # raw;
      trim_decimal_zeros(out)
    } else {
      let split = Text.size(raw) - decimals;
      let chars = chars_array(raw);
      let whole = chars_slice_to_text(chars, 0, split);
      let frac = chars_slice_to_text(chars, split, chars.size());
      trim_decimal_zeros(whole # "." # frac)
    }
  };

  public func keccak256(data : [Nat8]) : [Nat8] {
    let k = SHA3.Keccak(256);
    k.update(data);
    k.finalize()
  };

  public func rlp_encode_legacy_unsigned(
    nonce : Nat,
    gas_price : Nat,
    gas_limit : Nat,
    to20 : [Nat8],
    value : Nat,
    data : [Nat8],
    chain_id : Nat,
  ) : [Nat8] {
    rlp_list([
      rlp_bytes(nat_to_min_be(nonce)),
      rlp_bytes(nat_to_min_be(gas_price)),
      rlp_bytes(nat_to_min_be(gas_limit)),
      rlp_bytes(to20),
      rlp_bytes(nat_to_min_be(value)),
      rlp_bytes(data),
      rlp_bytes(nat_to_min_be(chain_id)),
      rlp_bytes([]),
      rlp_bytes([]),
    ])
  };

  public func rlp_encode_legacy_signed(
    nonce : Nat,
    gas_price : Nat,
    gas_limit : Nat,
    to20 : [Nat8],
    value : Nat,
    data : [Nat8],
    v : Nat,
    r : Nat,
    s : Nat,
  ) : [Nat8] {
    rlp_list([
      rlp_bytes(nat_to_min_be(nonce)),
      rlp_bytes(nat_to_min_be(gas_price)),
      rlp_bytes(nat_to_min_be(gas_limit)),
      rlp_bytes(to20),
      rlp_bytes(nat_to_min_be(value)),
      rlp_bytes(data),
      rlp_bytes(nat_to_min_be(v)),
      rlp_bytes(nat_to_min_be(r)),
      rlp_bytes(nat_to_min_be(s)),
    ])
  };

  public func rlp_encode_eip1559_unsigned(
    chain_id : Nat,
    nonce : Nat,
    max_priority_fee_per_gas : Nat,
    max_fee_per_gas : Nat,
    gas_limit : Nat,
    to20 : [Nat8],
    value : Nat,
    data : [Nat8],
  ) : [Nat8] {
    let payload = rlp_list([
      rlp_bytes(nat_to_min_be(chain_id)),
      rlp_bytes(nat_to_min_be(nonce)),
      rlp_bytes(nat_to_min_be(max_priority_fee_per_gas)),
      rlp_bytes(nat_to_min_be(max_fee_per_gas)),
      rlp_bytes(nat_to_min_be(gas_limit)),
      rlp_bytes(to20),
      rlp_bytes(nat_to_min_be(value)),
      rlp_bytes(data),
      rlp_list([]), // accessList
    ]);
    Array.append<Nat8>([0x02], payload)
  };

  public func rlp_encode_eip1559_signed(
    chain_id : Nat,
    nonce : Nat,
    max_priority_fee_per_gas : Nat,
    max_fee_per_gas : Nat,
    gas_limit : Nat,
    to20 : [Nat8],
    value : Nat,
    data : [Nat8],
    y_parity : Nat8,
    r : Nat,
    s : Nat,
  ) : [Nat8] {
    let payload = rlp_list([
      rlp_bytes(nat_to_min_be(chain_id)),
      rlp_bytes(nat_to_min_be(nonce)),
      rlp_bytes(nat_to_min_be(max_priority_fee_per_gas)),
      rlp_bytes(nat_to_min_be(max_fee_per_gas)),
      rlp_bytes(nat_to_min_be(gas_limit)),
      rlp_bytes(to20),
      rlp_bytes(nat_to_min_be(value)),
      rlp_bytes(data),
      rlp_list([]), // accessList
      rlp_bytes(nat_to_min_be(Nat8.toNat(y_parity))),
      rlp_bytes(nat_to_min_be(r)),
      rlp_bytes(nat_to_min_be(s)),
    ]);
    Array.append<Nat8>([0x02], payload)
  };

  public func u256_word(n0 : Nat) : Error.WalletResult<[Nat8]> {
    if (n0 >= MAX_U256_PLUS_ONE) return #Err(#InvalidInput("token amount is too large"));
    let out = Array.init<Nat8>(32, 0);
    var n = n0;
    var i : Nat = 32;
    while (i > 0) {
      i -= 1;
      out[i] := Nat8.fromNat(n % 256);
      n /= 256;
    };
    #Ok(Array.freeze(out))
  };

  func hex_digit(c : Char) : ?Nat {
    let n = Char.toNat32(c);
    if (n >= 48 and n <= 57) return ?Nat32.toNat(n - 48);
    if (n >= 65 and n <= 70) return ?Nat32.toNat(n - 55);
    if (n >= 97 and n <= 102) return ?Nat32.toNat(n - 87);
    null
  };

  func nat_to_min_be(n0 : Nat) : [Nat8] {
    if (n0 == 0) return [];
    let out = Buffer.Buffer<Nat8>(32);
    var n = n0;
    while (n > 0) {
      out.add(Nat8.fromNat(n % 256));
      n /= 256;
    };
    Array.reverse(Buffer.toArray(out))
  };

  func rlp_list(items : [[Nat8]]) : [Nat8] {
    let payload = concat_bytes(items);
    Array.append(rlp_length_prefix(payload.size(), 0xc0), payload)
  };

  func rlp_bytes(bytes : [Nat8]) : [Nat8] {
    if (bytes.size() == 1 and Nat8.toNat(bytes[0]) < 0x80) return bytes;
    Array.append(rlp_length_prefix(bytes.size(), 0x80), bytes)
  };

  func rlp_length_prefix(len : Nat, short_base : Nat) : [Nat8] {
    if (len <= 55) {
      [Nat8.fromNat(short_base + len)]
    } else {
      let lenBytes = nat_to_min_be(len);
      Array.append([Nat8.fromNat(short_base + 55 + lenBytes.size())], lenBytes)
    }
  };

  func concat_bytes(parts : [[Nat8]]) : [Nat8] {
    var total : Nat = 0;
    for (p in parts.vals()) { total += p.size() };
    let out = Buffer.Buffer<Nat8>(total);
    for (p in parts.vals()) {
      for (b in p.vals()) { out.add(b) };
    };
    Buffer.toArray(out)
  };

  func trim_decimal_zeros(s0 : Text) : Text {
    let chars = chars_array(s0);
    var dot : ?Nat = null;
    var i : Nat = 0;
    while (i < chars.size()) {
      if (chars[i] == '.') { dot := ?i };
      i += 1;
    };
    switch (dot) {
      case null s0;
      case (?d) {
        var end = chars.size();
        while (end > 0 and chars[end - 1] == '0') { end -= 1 };
        if (end == d + 1) { end -= 1 };
        chars_slice_to_text(chars, 0, end)
      };
    }
  };

  func repeat_text(piece : Text, n : Nat) : Text {
    var out = "";
    var i : Nat = 0;
    while (i < n) { out #= piece; i += 1 };
    out
  };

  func chars_array(t : Text) : [Char] {
    let b = Buffer.Buffer<Char>(Text.size(t));
    for (c in t.chars()) { b.add(c) };
    Buffer.toArray(b)
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
}

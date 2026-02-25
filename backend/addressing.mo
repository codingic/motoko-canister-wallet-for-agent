import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import MoError "mo:base/Error";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import AppConfig "./config/app_config";
import Error "./error";
import SHA256 "./sha256";
import SHA3 "./sha3";
import Types "./types";

module {
  let BECH32M_CONST : Nat32 = 0x2bc8_30a3;
  let BECH32_CHARSET : [Char] = [
    'q', 'p', 'z', 'r', 'y', '9', 'x', '8',
    'g', 'f', '2', 't', 'v', 'd', 'w', '0',
    's', '3', 'j', 'n', '5', '4', 'k', 'h',
    'c', 'e', '6', 'm', 'u', 'a', '7', 'l',
  ];
  let BECH32_POLYMOD_GEN : [Nat32] = [
    0x3b6a_57b2,
    0x2650_8e6d,
    0x1ea1_19fa,
    0x3d42_33dd,
    0x2a14_62b3,
  ];
  let SECP256K1_P : Nat = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
  let SECP256K1_N : Nat = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
  let SECP256K1_GX : Nat = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
  let SECP256K1_GY : Nat = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

  public type SchnorrAlgorithm = {
    #bip340secp256k1;
    #ed25519;
  };

  type EcdsaCurve = {
    #secp256k1;
  };

  type EcdsaKeyId = {
    curve : EcdsaCurve;
    name : Text;
  };

  type EcdsaPublicKeyArgs = {
    canister_id : ?Principal;
    derivation_path : [Blob];
    key_id : EcdsaKeyId;
  };

  type EcdsaPublicKeyResult = {
    public_key : Blob;
    chain_code : Blob;
  };

  type SignWithEcdsaArgs = {
    message_hash : Blob;
    derivation_path : [Blob];
    key_id : EcdsaKeyId;
  };

  type SignWithEcdsaResult = {
    signature : Blob;
  };

  type SchnorrKeyId = {
    algorithm : SchnorrAlgorithm;
    name : Text;
  };

  type SchnorrPublicKeyArgs = {
    canister_id : ?Principal;
    derivation_path : [Blob];
    key_id : SchnorrKeyId;
  };

  type SchnorrPublicKeyResult = {
    public_key : Blob;
    chain_code : Blob;
  };

  type DecodeResult<T> = {
    #ok : T;
    #err : Text;
  };

  type AffinePoint = {
    x : Nat;
    y : Nat;
  };

  let Management : actor {
    ecdsa_public_key : shared (EcdsaPublicKeyArgs) -> async EcdsaPublicKeyResult;
    schnorr_public_key : shared (SchnorrPublicKeyArgs) -> async SchnorrPublicKeyResult;
    sign_with_ecdsa : shared (SignWithEcdsaArgs) -> async SignWithEcdsaResult;
  } = actor "aaaaa-aa";

  public func derive_evm_address(network : Text) : async Error.WalletResult<Types.AddressResponse> {
    switch (await fetch_ecdsa_secp256k1_public_key()) {
      case (#Err(err)) #Err(err);
      case (#Ok((public_key, key_name))) {
        switch (evm20_from_sec1_public_key(public_key)) {
          case (#Err(err)) #Err(err);
          case (#Ok(evm20)) {
            let addr_hex = hex_encode(evm20);
            #Ok({
              network;
              address = "0x" # addr_hex;
              public_key_hex = hex_encode(public_key);
              key_name;
              message = ?"Derived from management canister ECDSA public key";
            })
          };
        }
      };
    }
  };

  public func evm20_from_sec1_public_key(public_key : [Nat8]) : Error.WalletResult<[Nat8]> {
    switch (secp256k1_uncompressed_no_prefix(public_key)) {
      case (#err(msg)) #Err(#Internal("invalid secp256k1 public key: " # msg));
      case (#ok(uncompressed_no_prefix)) {
        let hash = keccak256(uncompressed_no_prefix);
        if (hash.size() < 32) {
          return #Err(#Internal("unexpected keccak256 output length"));
        };
        #Ok(slice_bytes(hash, 12, 32))
      };
    }
  };

  public func fetch_ecdsa_secp256k1_public_key() : async Error.WalletResult<([Nat8], Text)> {
    let key_name = AppConfig.default_ecdsa_key_name();
    let args : EcdsaPublicKeyArgs = {
      canister_id = null;
      derivation_path = [];
      key_id = {
        curve = #secp256k1;
        name = key_name;
      };
    };
    try {
      let result = await Management.ecdsa_public_key(args);
      #Ok((Blob.toArray(result.public_key), key_name))
    } catch e {
      #Err(#Internal("ecdsa_public_key failed: " # MoError.message(e)))
    }
  };

  public func sign_ecdsa_secp256k1_prehash32(message_hash32 : [Nat8]) : async Error.WalletResult<[Nat8]> {
    if (message_hash32.size() != 32) {
      return #Err(#InvalidInput("ECDSA message_hash must be 32 bytes"));
    };
    let args : SignWithEcdsaArgs = {
      message_hash = Blob.fromArray(message_hash32);
      derivation_path = [];
      key_id = {
        curve = #secp256k1;
        name = AppConfig.default_ecdsa_key_name();
      };
    };
    try {
      let res = await Management.sign_with_ecdsa(args);
      let sig = Blob.toArray(res.signature);
      if (sig.size() != 64) {
        return #Err(#Internal("unexpected secp256k1 signature length: " # Nat32.toText(Nat32.fromNat(sig.size()))));
      };
      #Ok(sig)
    } catch e {
      #Err(#Internal("sign_with_ecdsa failed: " # MoError.message(e)))
    }
  };

  public func ecdsa_recovery_id_secp256k1_prehash32(
    message_hash32 : [Nat8],
    signature64 : [Nat8],
    public_key_sec1 : [Nat8],
  ) : Error.WalletResult<Nat8> {
    if (message_hash32.size() != 32) {
      return #Err(#InvalidInput("ECDSA message_hash must be 32 bytes"));
    };
    if (signature64.size() != 64) {
      return #Err(#InvalidInput("ECDSA signature must be 64 bytes (r||s)"));
    };

    let expected = switch (secp256k1_affine_from_sec1(public_key_sec1)) {
      case (#ok(p)) p;
      case (#err(msg)) return #Err(#InvalidInput("invalid secp256k1 public key: " # msg));
    };

    let r = bytes_to_nat(slice_bytes(signature64, 0, 32));
    let s = bytes_to_nat(slice_bytes(signature64, 32, 64));
    if (r == 0 or r >= SECP256K1_N or s == 0 or s >= SECP256K1_N) {
      return #Err(#InvalidInput("invalid secp256k1 signature scalars"));
    };
    let z = bytes_to_nat(message_hash32) % SECP256K1_N;

    var recid : Nat = 0;
    while (recid < 4) {
      switch (recover_ecdsa_pubkey_secp256k1(z, r, s, recid)) {
        case (?candidate) {
          if (candidate.x == expected.x and candidate.y == expected.y) {
            return #Ok(Nat8.fromNat(recid));
          };
        };
        case null {};
      };
      recid += 1;
    };
    #Err(#Internal("failed to recover matching secp256k1 public key"))
  };

  public func fetch_schnorr_public_key(
    algorithm : SchnorrAlgorithm
  ) : async Error.WalletResult<([Nat8], Text)> {
    let key_name = AppConfig.default_schnorr_key_name();
    let args : SchnorrPublicKeyArgs = {
      canister_id = null;
      derivation_path = [];
      key_id = {
        algorithm;
        name = key_name;
      };
    };
    try {
      let result = await Management.schnorr_public_key(args);
      #Ok((Blob.toArray(result.public_key), key_name))
    } catch e {
      #Err(#Internal("schnorr_public_key failed: " # MoError.message(e)))
    }
  };

  public func hex_encode(bytes : [Nat8]) : Text {
    let hexChars : [Char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
    var out = "";
    for (b in bytes.vals()) {
      let n = Nat8.toNat(b);
      out := out # Char.toText(hexChars[n / 16]) # Char.toText(hexChars[n % 16]);
    };
    out
  };

  public func base58_encode(bytes : [Nat8]) : Text {
    if (bytes.size() == 0) {
      return "";
    };

    var zeros : Nat = 0;
    while (zeros < bytes.size() and bytes[zeros] == 0) {
      zeros += 1;
    };

    let input = Array.thaw<Nat8>(bytes);
    let encoded = Buffer.Buffer<Nat8>(bytes.size() * 2);
    let alphabet = base58_alphabet_bytes();
    var start = zeros;

    while (start < input.size()) {
      var remainder : Nat = 0;
      var i = start;
      while (i < input.size()) {
        let value = (remainder * 256) + Nat8.toNat(input[i]);
        input[i] := Nat8.fromNat(value / 58);
        remainder := value % 58;
        i += 1;
      };
      encoded.add(alphabet[remainder]);
      while (start < input.size() and input[start] == 0) {
        start += 1;
      };
    };

    var z : Nat = 0;
    while (z < zeros) {
      encoded.add(alphabet[0]);
      z += 1;
    };

    let reversed = Array.reverse<Nat8>(Buffer.toArray(encoded));
    switch (Text.decodeUtf8(Blob.fromArray(reversed))) {
      case (?text) text;
      case null "";
    };
  };

  public func encode_segwit_v1_bech32m(hrp : Text, witness_program : [Nat8]) : Error.WalletResult<Text> {
    if (witness_program.size() != 32) {
      return #Err(Error.invalid_input("taproot witness program must be 32 bytes"));
    };

    switch (convert_bits(witness_program, 8, 5, true)) {
      case (#Err(err)) #Err(err);
      case (#Ok(converted)) {
        let data = Array.append<Nat8>([1], converted);
        bech32m_encode(hrp, data);
      };
    };
  };

  public func taproot_output_key_xonly_from_internal_bip340(
    internal_xonly : [Nat8]
  ) : Error.WalletResult<[Nat8]> {
    if (internal_xonly.size() != 32) {
      return #Err(Error.invalid_input("bip340 internal key must be 32 bytes"));
    };
    let p0 = switch (lift_x_even(bytes_to_nat(internal_xonly))) {
      case (#err(msg)) return #Err(#Internal("invalid bip340 internal key: " # msg));
      case (#ok(point)) point;
    };
    let tweakHash = tagged_hash("TapTweak", internal_xonly);
    if (tweakHash.size() != 32) {
      return #Err(#Internal("unexpected TapTweak hash length"));
    };
    let t = bytes_to_nat(tweakHash);
    if (t >= SECP256K1_N) {
      return #Err(#Internal("TapTweak scalar out of range"));
    };
    let q = switch (point_add(?p0, point_mul_generator(t))) {
      case null return #Err(#Internal("taproot output key is point at infinity"));
      case (?point) point;
    };
    #Ok(nat_to_fixed_32(q.x))
  };

  func base58_alphabet_bytes() : [Nat8] {
    Blob.toArray(Text.encodeUtf8("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"));
  };

  func keccak256(bytes : [Nat8]) : [Nat8] {
    let k = SHA3.Keccak(256);
    k.update(bytes);
    k.finalize();
  };

  func sha256(bytes : [Nat8]) : [Nat8] {
    Blob.toArray(SHA256.fromArray(#sha256, bytes))
  };

  func tagged_hash(tag : Text, msg : [Nat8]) : [Nat8] {
    let tagHash = sha256(Blob.toArray(Text.encodeUtf8(tag)));
    sha256(Array.append(Array.append(tagHash, tagHash), msg))
  };

  func secp256k1_uncompressed_no_prefix(pub : [Nat8]) : DecodeResult<[Nat8]> {
    if (pub.size() == 65) {
      if (pub[0] != 0x04) {
        return #err("unexpected uncompressed public key format");
      };
      return #ok(slice_bytes(pub, 1, 65));
    };

    if (pub.size() == 33) {
      let prefix = pub[0];
      if (prefix != 0x02 and prefix != 0x03) {
        return #err("unexpected compressed public key format");
      };
      let x_bytes = slice_bytes(pub, 1, 33);
      let x = bytes_to_nat(x_bytes);
      let p = SECP256K1_P;
      if (x >= p) {
        return #err("invalid compressed public key x");
      };

      let y_squared = (mod_mul(mod_mul(x, x, p), x, p) + 7) % p;
      let y_root = mod_exp(y_squared, (p + 1) / 4, p);
      if (mod_mul(y_root, y_root, p) != y_squared) {
        return #err("invalid compressed public key point");
      };

      let want_odd = (prefix == 0x03);
      let root_odd = (y_root % 2 == 1);
      let y : Nat = if (root_odd == want_odd) {
        y_root
      } else {
        if (y_root <= p) { (p - y_root) % p } else {
          return #err("invalid compressed public key root");
        };
      };

      return #ok(Array.append<Nat8>(nat_to_fixed_32(x), nat_to_fixed_32(y)));
    };

    #err("unexpected public key length");
  };

  func secp256k1_affine_from_sec1(pub : [Nat8]) : DecodeResult<AffinePoint> {
    switch (secp256k1_uncompressed_no_prefix(pub)) {
      case (#err(msg)) #err(msg);
      case (#ok(raw)) {
        if (raw.size() != 64) return #err("unexpected uncompressed key length");
        #ok({
          x = bytes_to_nat(slice_bytes(raw, 0, 32));
          y = bytes_to_nat(slice_bytes(raw, 32, 64));
        })
      };
    }
  };

  func mod_mul(a : Nat, b : Nat, m : Nat) : Nat {
    (a * b) % m
  };

  func mod_add(a : Nat, b : Nat, m : Nat) : Nat {
    let x = (a % m) + (b % m);
    if (x >= m) x - m else x
  };

  func mod_sub(a : Nat, b : Nat, m : Nat) : Nat {
    let aa = a % m;
    let bb = b % m;
    if (aa >= bb) {
      aa - bb
    } else {
      m - ((bb - aa) % m)
    }
  };

  func mod_inv(a : Nat, m : Nat) : Nat {
    // m is prime for secp256k1 field operations.
    mod_exp(a % m, m - 2, m)
  };

  func mod_exp(base : Nat, exp : Nat, m : Nat) : Nat {
    if (m == 1) {
      return 0;
    };
    var result : Nat = 1;
    var b = base % m;
    var e = exp;
    while (e > 0) {
      if (e % 2 == 1) {
        result := mod_mul(result, b, m);
      };
      b := mod_mul(b, b, m);
      e /= 2;
    };
    result
  };

  func bytes_to_nat(bytes : [Nat8]) : Nat {
    var acc : Nat = 0;
    for (b in bytes.vals()) {
      acc := (acc * 256) + Nat8.toNat(b);
    };
    acc
  };

  func lift_x_even(x : Nat) : DecodeResult<AffinePoint> {
    let p = SECP256K1_P;
    if (x >= p) return #err("x out of range");
    let y2 = mod_add(mod_mul(mod_mul(x, x, p), x, p), 7, p);
    let yRoot = mod_exp(y2, (p + 1) / 4, p);
    if (mod_mul(yRoot, yRoot, p) != y2) {
      return #err("x does not lie on secp256k1");
    };
    let yEven = if ((yRoot % 2) == 0) yRoot else mod_sub(p, yRoot, p);
    #ok({ x; y = yEven })
  };

  func lift_x_with_parity(x : Nat, wantOdd : Bool) : DecodeResult<AffinePoint> {
    switch (lift_x_even(x)) {
      case (#err(msg)) #err(msg);
      case (#ok(p)) {
        if (((p.y % 2) == 1) == wantOdd) {
          #ok(p)
        } else {
          #ok({ x = p.x; y = mod_sub(SECP256K1_P, p.y, SECP256K1_P) })
        }
      };
    }
  };

  func point_double(p0 : AffinePoint) : ?AffinePoint {
    let p = SECP256K1_P;
    if (p0.y == 0) return null;
    let x2 = mod_mul(p0.x, p0.x, p);
    let num = mod_add(mod_add(x2, x2, p), x2, p); // 3*x^2
    let den = mod_mul(2, p0.y, p);
    if (den == 0) return null;
    let lambda = mod_mul(num, mod_inv(den, p), p);
    let x3 = mod_sub(mod_sub(mod_mul(lambda, lambda, p), p0.x, p), p0.x, p);
    let y3 = mod_sub(mod_mul(lambda, mod_sub(p0.x, x3, p), p), p0.y, p);
    ?{ x = x3; y = y3 }
  };

  func point_add(pA : ?AffinePoint, pB : ?AffinePoint) : ?AffinePoint {
    switch (pA, pB) {
      case (null, _) pB;
      case (_, null) pA;
      case (?(a), ?(b)) {
        let p = SECP256K1_P;
        if (a.x == b.x) {
          if (mod_add(a.y, b.y, p) == 0) {
            null
          } else {
            point_double(a)
          }
        } else {
          let num = mod_sub(b.y, a.y, p);
          let den = mod_sub(b.x, a.x, p);
          if (den == 0) {
            null
          } else {
            let lambda = mod_mul(num, mod_inv(den, p), p);
            let x3 = mod_sub(mod_sub(mod_mul(lambda, lambda, p), a.x, p), b.x, p);
            let y3 = mod_sub(mod_mul(lambda, mod_sub(a.x, x3, p), p), a.y, p);
            ?{ x = x3; y = y3 }
          }
        }
      };
    }
  };

  func point_mul(p0 : ?AffinePoint, k0 : Nat) : ?AffinePoint {
    switch (p0) {
      case null null;
      case (?_) {
        var n = k0 % SECP256K1_N;
        if (n == 0) return null;
        var result : ?AffinePoint = null;
        var addend : ?AffinePoint = p0;
        while (n > 0) {
          if ((n % 2) == 1) {
            result := point_add(result, addend);
          };
          addend := point_add(addend, addend);
          n /= 2;
        };
        result
      };
    }
  };

  func point_mul_generator(k : Nat) : ?AffinePoint {
    if (k == 0) return null;
    let g : AffinePoint = { x = SECP256K1_GX; y = SECP256K1_GY };
    var n = k % SECP256K1_N;
    if (n == 0) return null;
    var result : ?AffinePoint = null;
    var addend : ?AffinePoint = ?g;
    while (n > 0) {
      if ((n % 2) == 1) {
        result := point_add(result, addend);
      };
      addend := point_add(addend, addend);
      n /= 2;
    };
    result
  };

  func recover_ecdsa_pubkey_secp256k1(z : Nat, r : Nat, s : Nat, recid : Nat) : ?AffinePoint {
    if (recid >= 4) return null;
    let j = recid / 2;
    let wantOdd = ((recid % 2) == 1);
    let x = r + (j * SECP256K1_N);
    if (x >= SECP256K1_P) return null;

    let rPoint = switch (lift_x_with_parity(x, wantOdd)) {
      case (#err(_)) return null;
      case (#ok(p)) p;
    };

    // Valid ECDSA recovery point must have order n.
    if (point_mul(?rPoint, SECP256K1_N) != null) return null;

    let rInv = mod_inv(r, SECP256K1_N);
    let sr = mod_mul(s, rInv, SECP256K1_N);
    let zr = mod_mul(z, rInv, SECP256K1_N);
    let negZr = if (zr == 0) 0 else (SECP256K1_N - zr);

    point_add(
      point_mul_generator(negZr),
      point_mul(?rPoint, sr),
    )
  };

  func nat_to_fixed_32(n0 : Nat) : [Nat8] {
    let out = Array.init<Nat8>(32, 0);
    var n = n0;
    var i : Nat = 32;
    while (i > 0) {
      i -= 1;
      out[i] := Nat8.fromNat(n % 256);
      n /= 256;
    };
    Array.freeze(out)
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

  func convert_bits(
    data : [Nat8],
    from_bits : Nat32,
    to_bits : Nat32,
    pad : Bool,
  ) : Error.WalletResult<[Nat8]> {
    var acc : Nat32 = 0;
    var bits : Nat32 = 0;
    let maxv : Nat32 = ((1 : Nat32) << to_bits) - 1;
    let max_acc : Nat32 = ((1 : Nat32) << (from_bits + to_bits - 1)) - 1;
    let out = Buffer.Buffer<Nat8>(data.size() + 8);

    for (value in data.vals()) {
      let v : Nat32 = Nat32.fromNat(Nat8.toNat(value));
      if ((v >> from_bits) != 0) {
        return #Err(Error.invalid_input("invalid bit group value"));
      };
      acc := ((acc << from_bits) | v) & max_acc;
      bits += from_bits;
      while (bits >= to_bits) {
        bits -= to_bits;
        out.add(Nat8.fromNat(Nat32.toNat((acc >> bits) & maxv)));
      };
    };

    if (pad) {
      if (bits > 0) {
        out.add(Nat8.fromNat(Nat32.toNat((acc << (to_bits - bits)) & maxv)));
      };
    } else {
      if (bits >= from_bits or (((acc << (to_bits - bits)) & maxv) != 0)) {
        return #Err(Error.invalid_input("invalid padding"));
      };
    };

    #Ok(Buffer.toArray(out));
  };

  func bech32m_encode(hrp : Text, data : [Nat8]) : Error.WalletResult<Text> {
    if (Text.size(hrp) == 0) {
      return #Err(Error.invalid_input("bech32 hrp is required"));
    };
    for (c in hrp.chars()) {
      if (not is_ascii_lowercase_or_digit(c)) {
        return #Err(Error.invalid_input("bech32 hrp must be lowercase ascii"));
      };
    };
    for (v in data.vals()) {
      if (Nat8.toNat(v) >= 32) {
        return #Err(Error.invalid_input("bech32 data values must be < 32"));
      };
    };

    let checksum = bech32m_checksum(hrp, data);
    var out = hrp # "1";
    for (v in data.vals()) {
      out := out # Char.toText(BECH32_CHARSET[Nat8.toNat(v)]);
    };
    for (v in checksum.vals()) {
      out := out # Char.toText(BECH32_CHARSET[Nat8.toNat(v)]);
    };
    #Ok(out);
  };

  func bech32m_checksum(hrp : Text, data : [Nat8]) : [Nat8] {
    let values = Array.append<Nat8>(
      Array.append<Nat8>(hrp_expand(hrp), data),
      [0, 0, 0, 0, 0, 0],
    );
    let polymod = bech32_polymod(values) ^ BECH32M_CONST;
    Array.tabulate<Nat8>(
      6,
      func(i : Nat) : Nat8 {
        let shift = Nat32.fromNat(5 * (5 - i));
        Nat8.fromNat(Nat32.toNat((polymod >> shift) & (0x1f : Nat32)));
      },
    );
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
    Buffer.toArray(out);
  };

  func bech32_polymod(values : [Nat8]) : Nat32 {
    var chk : Nat32 = 1;
    for (value in values.vals()) {
      let b : Nat32 = chk >> (25 : Nat32);
      chk := ((chk & (0x01ff_ffff : Nat32)) << (5 : Nat32)) ^ Nat32.fromNat(Nat8.toNat(value));
      var i : Nat = 0;
      while (i < BECH32_POLYMOD_GEN.size()) {
        if (((b >> Nat32.fromNat(i)) & (1 : Nat32)) != 0) {
          chk := chk ^ BECH32_POLYMOD_GEN[i];
        };
        i += 1;
      };
    };
    chk
  };

  func is_ascii_lowercase_or_digit(c : Char) : Bool {
    let n = Char.toNat32(c);
    ((n >= (48 : Nat32) and n <= (57 : Nat32)) or (n >= (97 : Nat32) and n <= (122 : Nat32)))
  };
}

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Error "../error";
import Sha256 "../sha256";

module {
  let SPL_TOKEN_PROGRAM_ID_BASE58 : Text = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
  let SPL_ASSOCIATED_TOKEN_PROGRAM_ID_BASE58 : Text = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
  let ED25519_P : Nat = 57896044618658097711785492504343953926634992332820282019728792003956564819949;
  let ED25519_D : Nat = 37095705934669439343138083508754565189542113879843219016388785533085940283555;
  let ED25519_SQRT_M1 : Nat = 19681161376707505956807079304988542015446066515923890162744021073123829784752;
  let ED25519_SQRT_EXP : Nat = 7237005577332262213973186563042994240829374041602535252466099000494570602494;

  public func decode_solana_pubkey(value : Text) : Error.WalletResult<[Nat8]> {
    let bytes = switch (base58_decode(Text.trim(value, #char ' '))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (bytes.size() != 32) {
      return #Err(#InvalidInput("solana pubkey/blockhash must decode to 32 bytes (base58)"));
    };
    #Ok(bytes)
  };

  public func encode_system_transfer_message(
    from_pubkey : [Nat8],
    to_pubkey : [Nat8],
    recent_blockhash : [Nat8],
    lamports : Nat,
  ) : Error.WalletResult<[Nat8]> {
    if (from_pubkey.size() != 32 or to_pubkey.size() != 32 or recent_blockhash.size() != 32) {
      return #Err(#InvalidInput("solana pubkeys/blockhash must be 32 bytes"));
    };
    let out = Buffer.Buffer<Nat8>(256);

    out.add(1);
    out.add(0);
    out.add(1);

    append_bytes(out, shortvec_len(3));
    append_bytes(out, from_pubkey);
    append_bytes(out, to_pubkey);
    append_bytes(out, solana_system_program_id());

    append_bytes(out, recent_blockhash);
    append_bytes(out, shortvec_len(1));

    out.add(2);
    append_bytes(out, shortvec_len(2));
    out.add(0);
    out.add(1);

    let data = Buffer.Buffer<Nat8>(12);
    append_u32_le(data, 2);
    append_u64_le(data, lamports);
    let dataArr = Buffer.toArray(data);
    append_bytes(out, shortvec_len(dataArr.size()));
    append_bytes(out, dataArr);

    #Ok(Buffer.toArray(out))
  };

  public func encode_signed_transaction(signature : [Nat8], message : [Nat8]) : [Nat8] {
    let out = Buffer.Buffer<Nat8>(1 + signature.size() + message.size());
    append_bytes(out, shortvec_len(1));
    append_bytes(out, signature);
    append_bytes(out, message);
    Buffer.toArray(out)
  };

  public func encode_spl_transfer_checked_message(
    owner_pubkey : [Nat8],
    source_token_account : [Nat8],
    dest_token_account : [Nat8],
    destination_owner : [Nat8],
    mint : [Nat8],
    recent_blockhash : [Nat8],
    amount_raw : Nat,
    decimals : Nat8,
    create_destination_ata : Bool,
  ) : Error.WalletResult<[Nat8]> {
    if (owner_pubkey.size() != 32 or source_token_account.size() != 32 or dest_token_account.size() != 32 or mint.size() != 32 or recent_blockhash.size() != 32) {
      return #Err(#InvalidInput("solana pubkeys/blockhash must be 32 bytes"));
    };
    let tokenProgramId = switch (decode_solana_pubkey(SPL_TOKEN_PROGRAM_ID_BASE58)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let ataProgramIdOpt : ?[Nat8] = if (create_destination_ata) {
      switch (decode_solana_pubkey(SPL_ASSOCIATED_TOKEN_PROGRAM_ID_BASE58)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) ?v;
      }
    } else {
      null
    };

    let out = Buffer.Buffer<Nat8>(320);
    out.add(1);
    out.add(0);
    out.add(if (create_destination_ata) 5 else 2);

    append_bytes(out, shortvec_len(if (create_destination_ata) 8 else 5));
    append_bytes(out, owner_pubkey);
    append_bytes(out, source_token_account);
    append_bytes(out, dest_token_account);
    append_bytes(out, mint);
    if (create_destination_ata) {
      append_bytes(out, destination_owner);
      append_bytes(out, solana_system_program_id());
    };
    append_bytes(out, tokenProgramId);
    switch (ataProgramIdOpt) {
      case (?ataProgramId) append_bytes(out, ataProgramId);
      case null {};
    };

    append_bytes(out, recent_blockhash);
    append_bytes(out, shortvec_len(if (create_destination_ata) 2 else 1));

    if (create_destination_ata) {
      out.add(7);
      append_bytes(out, shortvec_len(6));
      out.add(0);
      out.add(2);
      out.add(4);
      out.add(3);
      out.add(5);
      out.add(6);
      append_bytes(out, shortvec_len(1));
      out.add(1);
    };

    out.add(if (create_destination_ata) 6 else 4);
    append_bytes(out, shortvec_len(4));
    out.add(1);
    out.add(3);
    out.add(2);
    out.add(0);

    let data = Buffer.Buffer<Nat8>(10);
    data.add(12);
    append_u64_le(data, amount_raw);
    data.add(decimals);
    let dataArr = Buffer.toArray(data);
    append_bytes(out, shortvec_len(dataArr.size()));
    append_bytes(out, dataArr);

    #Ok(Buffer.toArray(out))
  };

  public func derive_associated_token_address(
    owner : [Nat8],
    mint : [Nat8],
  ) : Error.WalletResult<[Nat8]> {
    if (owner.size() != 32 or mint.size() != 32) {
      return #Err(#InvalidInput("solana pubkeys must be 32 bytes"));
    };
    let tokenProgramId = switch (decode_solana_pubkey(SPL_TOKEN_PROGRAM_ID_BASE58)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let ataProgramId = switch (decode_solana_pubkey(SPL_ASSOCIATED_TOKEN_PROGRAM_ID_BASE58)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    find_program_address([owner, tokenProgramId, mint], ataProgramId)
  };

  func find_program_address(
    seeds : [[Nat8]],
    program_id : [Nat8],
  ) : Error.WalletResult<[Nat8]> {
    if (program_id.size() != 32) {
      return #Err(#InvalidInput("solana program id must be 32 bytes"));
    };
    var bump : Nat = 256;
    while (bump > 0) {
      bump -= 1;
      let bumpSeed : [Nat8] = [Nat8.fromNat(bump)];
      let allSeeds = Array.append<[Nat8]>(seeds, [bumpSeed]);
      switch (try_create_program_address(allSeeds, program_id)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(?addr)) return #Ok(addr);
        case (#Ok(null)) {};
      };
    };
    #Err(#Internal("failed to derive valid Solana program-derived address"))
  };

  func try_create_program_address(
    seeds : [[Nat8]],
    program_id : [Nat8],
  ) : Error.WalletResult<?[Nat8]> {
    for (seed in seeds.vals()) {
      if (seed.size() > 32) {
        return #Err(#InvalidInput("solana PDA seed length exceeds 32 bytes"));
      };
    };
    if (program_id.size() != 32) {
      return #Err(#InvalidInput("solana program id must be 32 bytes"));
    };
    let pdaMarker = pda_marker_bytes();
    var total : Nat = program_id.size() + pdaMarker.size();
    for (seed in seeds.vals()) { total += seed.size() };
    let preimage = Buffer.Buffer<Nat8>(total);
    for (seed in seeds.vals()) { append_bytes(preimage, seed) };
    append_bytes(preimage, program_id);
    append_bytes(preimage, pdaMarker);
    let hash = Blob.toArray(Sha256.fromArray(#sha256, Buffer.toArray(preimage)));
    if (is_on_ed25519_curve(hash)) {
      #Ok(null)
    } else {
      #Ok(?hash)
    }
  };

  func is_on_ed25519_curve(candidate : [Nat8]) : Bool {
    if (candidate.size() != 32) return false;

    let last = Nat8.toNat(candidate[31]);
    let signBit : Nat = if (last >= 128) 1 else 0;
    let yBytes = Array.tabulate<Nat8>(
      32,
      func(i : Nat) : Nat8 {
        if (i == 31) {
          Nat8.fromNat(last % 128)
        } else {
          candidate[i]
        }
      },
    );
    let y = le_bytes_to_nat(yBytes);
    if (y >= ED25519_P) return false;

    let y2 = mul_mod_p(y, y);
    let u = sub_mod_p(y2, 1);
    let v = add_mod_p(mul_mod_p(ED25519_D, y2), 1);
    if (v == 0) return false;
    let z = mul_mod_p(u, inv_mod_p(v));
    let x0 = switch (sqrt_mod_p_25519(z)) {
      case (?x) x;
      case null return false;
    };
    if (x0 == 0 and signBit == 1) return false;
    true
  };

  func le_bytes_to_nat(bytes : [Nat8]) : Nat {
    var n : Nat = 0;
    var i = bytes.size();
    while (i > 0) {
      i -= 1;
      n := (n * 256) + Nat8.toNat(bytes[i]);
    };
    n
  };

  func sqrt_mod_p_25519(a0 : Nat) : ?Nat {
    let a = a0 % ED25519_P;
    if (a == 0) return ?0;
    let x = pow_mod(a, ED25519_SQRT_EXP, ED25519_P);
    if (mul_mod_p(x, x) == a) return ?x;
    let xAlt = mul_mod_p(x, ED25519_SQRT_M1);
    if (mul_mod_p(xAlt, xAlt) == a) return ?xAlt;
    null
  };

  func pow_mod(base0 : Nat, exp0 : Nat, modulus : Nat) : Nat {
    if (modulus == 1) return 0;
    var base = base0 % modulus;
    var exp = exp0;
    var acc : Nat = 1 % modulus;
    while (exp > 0) {
      if ((exp % 2) == 1) {
        acc := (acc * base) % modulus;
      };
      exp /= 2;
      base := (base * base) % modulus;
    };
    acc
  };

  func inv_mod_p(a : Nat) : Nat {
    pow_mod(a, ED25519_P - 2, ED25519_P)
  };

  func add_mod_p(a0 : Nat, b0 : Nat) : Nat {
    let a = a0 % ED25519_P;
    let b = b0 % ED25519_P;
    let s = a + b;
    if (s >= ED25519_P) s - ED25519_P else s
  };

  func sub_mod_p(a0 : Nat, b0 : Nat) : Nat {
    let a = a0 % ED25519_P;
    let b = b0 % ED25519_P;
    if (a >= b) {
      a - b
    } else {
      ED25519_P - (b - a)
    }
  };

  func mul_mod_p(a0 : Nat, b0 : Nat) : Nat {
    ((a0 % ED25519_P) * (b0 % ED25519_P)) % ED25519_P
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

  func solana_system_program_id() : [Nat8] {
    Array.tabulate<Nat8>(32, func(_ : Nat) : Nat8 = 0)
  };

  func pda_marker_bytes() : [Nat8] {
    Blob.toArray(Text.encodeUtf8("ProgramDerivedAddress"))
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

  func shortvec_len(value0 : Nat) : [Nat8] {
    let out = Buffer.Buffer<Nat8>(5);
    var value = value0;
    label l loop {
      var elem : Nat = value % 128;
      value /= 128;
      if (value == 0) {
        out.add(Nat8.fromNat(elem));
        break l;
      };
      elem += 128;
      out.add(Nat8.fromNat(elem));
    };
    Buffer.toArray(out)
  };

  func append_bytes(buf : Buffer.Buffer<Nat8>, bytes : [Nat8]) {
    for (b in bytes.vals()) { buf.add(b) };
  };

  func append_u32_le(buf : Buffer.Buffer<Nat8>, n : Nat) {
    var v = n;
    var i : Nat = 0;
    while (i < 4) {
      buf.add(Nat8.fromNat(v % 256));
      v /= 256;
      i += 1;
    };
  };

  func append_u64_le(buf : Buffer.Buffer<Nat8>, n : Nat) {
    var v = n;
    var i : Nat = 0;
    while (i < 8) {
      buf.add(Nat8.fromNat(v % 256));
      v /= 256;
      i += 1;
    };
  };
}

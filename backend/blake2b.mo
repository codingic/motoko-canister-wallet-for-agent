import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Error "./error";

module {
  let IV : [Nat64] = [
    0x6A09E667F3BCC908 : Nat64,
    0xBB67AE8584CAA73B : Nat64,
    0x3C6EF372FE94F82B : Nat64,
    0xA54FF53A5F1D36F1 : Nat64,
    0x510E527FADE682D1 : Nat64,
    0x9B05688C2B3E6C1F : Nat64,
    0x1F83D9ABFB41BD6B : Nat64,
    0x5BE0CD19137E2179 : Nat64,
  ];

  let SIGMA : [[Nat]] = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  ];

  public func hash256_short(input : [Nat8]) : Error.WalletResult<[Nat8]> {
    hash256(input)
  };

  public func hash256(input : [Nat8]) : Error.WalletResult<[Nat8]> {
    let h = Array.init<Nat64>(8, 0 : Nat64);
    var i : Nat = 0;
    while (i < 8) {
      h[i] := IV[i];
      i += 1;
    };
    // Parameter block: digest_len=32, key_len=0, fanout=1, depth=1
    h[0] := Nat64.bitxor(h[0], 0x01010020 : Nat64);

    if (input.size() == 0) {
      let zeroBlock = Array.init<Nat8>(128, 0);
      let m0 = block_to_words(Array.freeze(zeroBlock));
      compress(h, m0, 0 : Nat64, 0 : Nat64, true);
      return #Ok(finalize32(h));
    };

    var offset : Nat = 0;
    while (offset < input.size()) {
      let remaining = input.size() - offset;
      let chunk = if (remaining > 128) 128 else remaining;
      let isLast = (offset + chunk == input.size());
      let block = Array.init<Nat8>(128, 0);
      var j : Nat = 0;
      while (j < chunk) {
        block[j] := input[offset + j];
        j += 1;
      };
      let words = block_to_words(Array.freeze(block));
      let total = offset + chunk;
      compress(h, words, Nat64.fromNat(total), 0 : Nat64, isLast);
      offset += chunk;
    };

    #Ok(finalize32(h))
  };

  func compress(
    h : [var Nat64],
    m : [Nat64],
    t0 : Nat64,
    t1 : Nat64,
    isLast : Bool,
  ) {
    let v = Array.init<Nat64>(16, 0 : Nat64);
    var i : Nat = 0;
    while (i < 8) {
      v[i] := h[i];
      v[i + 8] := IV[i];
      i += 1;
    };
    v[12] := Nat64.bitxor(v[12], t0);
    v[13] := Nat64.bitxor(v[13], t1);
    if (isLast) {
      v[14] := Nat64.bitxor(v[14], 0xffff_ffff_ffff_ffff : Nat64);
    };

    var r : Nat = 0;
    while (r < 12) {
      let s = SIGMA[r];
      g(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
      g(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
      g(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
      g(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
      g(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
      g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
      g(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
      g(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
      r += 1;
    };

    i := 0;
    while (i < 8) {
      h[i] := Nat64.bitxor(h[i], Nat64.bitxor(v[i], v[i + 8]));
      i += 1;
    };
  };

  func g(
    v : [var Nat64],
    a : Nat,
    b : Nat,
    c : Nat,
    d : Nat,
    x : Nat64,
    y : Nat64,
  ) {
    v[a] +%= v[b];
    v[a] +%= x;
    v[d] := Nat64.bitrotRight(Nat64.bitxor(v[d], v[a]), 32);
    v[c] +%= v[d];
    v[b] := Nat64.bitrotRight(Nat64.bitxor(v[b], v[c]), 24);
    v[a] +%= v[b];
    v[a] +%= y;
    v[d] := Nat64.bitrotRight(Nat64.bitxor(v[d], v[a]), 16);
    v[c] +%= v[d];
    v[b] := Nat64.bitrotRight(Nat64.bitxor(v[b], v[c]), 63);
  };

  func block_to_words(block128 : [Nat8]) : [Nat64] {
    let m = Array.init<Nat64>(16, 0 : Nat64);
    var j : Nat = 0;
    while (j < 16) {
      m[j] := read_u64_le(block128, j * 8);
      j += 1;
    };
    Array.freeze(m)
  };

  func finalize32(h : [var Nat64]) : [Nat8] {
    let out = Array.init<Nat8>(32, 0);
    var k : Nat = 0;
    while (k < 4) {
      write_u64_le(out, k * 8, h[k]);
      k += 1;
    };
    Array.freeze(out)
  };

  func read_u64_le(bytes : [Nat8], off : Nat) : Nat64 {
    var out : Nat64 = 0;
    var i : Nat = 0;
    while (i < 8) {
      out +%= Nat64.bitshiftLeft(Nat64.fromNat(Nat8.toNat(bytes[off + i])), Nat64.fromNat(i * 8));
      i += 1;
    };
    out
  };

  func write_u64_le(dest : [var Nat8], off : Nat, word : Nat64) {
    var i : Nat = 0;
    while (i < 8) {
      let shifted = Nat64.bitshiftRight(word, Nat64.fromNat(i * 8));
      dest[off + i] := Nat8.fromNat(Nat64.toNat(shifted % (256 : Nat64)));
      i += 1;
    };
  };
}

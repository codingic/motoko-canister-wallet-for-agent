import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Error "../error";
import SHA256 "../sha256";

module {
  public let TON_WORKCHAIN_BASECHAIN : Nat8 = 0;
  public let TON_WALLET_V4R2_WALLET_ID : Nat32 = 698_983_191;
  public let TON_JETTON_OP_TRANSFER : Nat32 = 0x0f8a_7ea5;

  // Wallet V4R2 code BOC hex (compiled wallet v4r2 code cell).
  // Source mirrored from public TON examples / tonweb wallet sources.
  let TON_WALLET_V4R2_CODE_BOC_HEX : Text =
    "b5ee9c7241021401000281000114ff00f4a413f4bcf2c80b01020120020d020148030402dcd020d749c120915b8f6320d70b1f2082106578746ebd21821073696e74bdb0925f03e082106578746eba8eb48020d72101d074d721fa4030fa44f828fa443058bd915be0ed44d0810141d721f4058307f40e6fa1319130e18040d721707fdb3ce03120d749810280b99130e070e2100f020120050c020120060902016e07080019adce76a2684020eb90eb85ffc00019af1df6a2684010eb90eb858fc00201480a0b0017b325fb51341c75c875c2c7e00011b262fb513435c280200019be5f0f6a2684080a0eb90fa02c0102f20e011e20d70b1f82107369676ebaf2e08a7f0f01e68ef0eda2edfb218308d722028308d723208020d721d31fd31fd31fed44d0d200d31f20d31fd3ffd70a000af90140ccf9109a28945f0adb31e1f2c087df02b35007b0f2d0845125baf2e0855036baf2e086f823bbf2d0882292f800de01a47fc8ca00cb1f01cf16c9ed542092f80fde70db3cd81003f6eda2edfb02f404216e926c218e4c0221d73930709421c700b38e2d01d72820761e436c20d749c008f2e09320d74ac002f2e09320d71d06c712c2005230b0f2d089d74cd7393001a4e86c128407bbf2e093d74ac000f2e093ed55e2d20001c000915be0ebd72c08142091709601d72c081c12e25210b1e30f20d74a111213009601fa4001fa44f828fa443058baf2e091ed44d0810141d718f405049d7fc8ca0040048307f453f2e08b8e14038307f45bf2e08c22d70a00216e01b3b0f2d090e2c85003cf1612f400c9ed54007230d72c08248e2d21f2e092d200ed44d0d2005113baf2d08f54503091319c01810140d721d70a00f2e08ee2c8ca0058cf16c9ed5493f2c08de20010935bdb31e1d74cd0b4d6c35e";

  let BASE64_URL_ALPHABET : [Char] = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
    'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
    'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
    'y', 'z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    '-', '_',
  ];
  let BASE64_STD_ALPHABET : [Char] = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
    'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
    'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
    'y', 'z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    '+', '/',
  ];

  type ParsedCell = {
    bits : [Bool];
    refs : [Nat];
  };

  type FlatCell = {
    bits : [Bool];
    refs : [Nat];
  };

  public type TonAddress = {
    workchain : Nat8;
    hash : [Nat8];
    bounceable : ?Bool;
    test_only : Bool;
  };

  public type Cell = {
    bits : [Bool];
    refs : [Cell];
  };

  public class CellBuilder() {
    let bitsBuf = Buffer.Buffer<Bool>(64);
    let refsBuf = Buffer.Buffer<Cell>(2);

    public func store_bit(v : Bool) {
      bitsBuf.add(v);
    };

    public func store_bits(bits : [Bool]) {
      for (b in bits.vals()) { bitsBuf.add(b) };
    };

    public func store_uint(v : Nat, bitCount : Nat) {
      var i : Nat = 0;
      while (i < bitCount) {
        let shift = (bitCount - 1) - i;
        let bit = ((v / pow2(shift)) % 2) == 1;
        bitsBuf.add(bit);
        i += 1;
      };
    };

    public func store_u32(v : Nat32) {
      store_uint(Nat32.toNat(v), 32);
    };

    public func store_u64(v : Nat) {
      store_uint(v, 64);
    };

    public func store_byte(b : Nat8) {
      store_uint(Nat8.toNat(b), 8);
    };

    public func store_bytes(bytes : [Nat8]) {
      for (b in bytes.vals()) {
        store_byte(b);
      };
    };

    public func store_ref(cell : Cell) {
      refsBuf.add(cell);
    };

    public func store_string_tail(text : Text) {
      store_bytes(Blob.toArray(Text.encodeUtf8(text)));
    };

    public func store_maybe_ref(cell : ?Cell) {
      switch (cell) {
        case (?c) {
          store_bit(true);
          refsBuf.add(c);
        };
        case null {
          store_bit(false);
        };
      }
    };

    public func store_coins(amount : Nat) : Error.WalletResult<()> {
      if (amount == 0) {
        store_uint(0, 4);
        return #Ok(());
      };
      let bytes = nat_to_be_bytes(amount);
      if (bytes.size() > 15) {
        return #Err(Error.invalid_input("TON coin value is too large"));
      };
      store_uint(bytes.size(), 4);
      store_bytes(bytes);
      #Ok(())
    };

    public func store_msg_address(address : ?TonAddress) : Error.WalletResult<()> {
      switch (address) {
        case null {
          // addr_none$00
          store_uint(0, 2);
          #Ok(())
        };
        case (?addr) {
          if (addr.hash.size() != 32) {
            return #Err(Error.invalid_input("TON address hash must be 32 bytes"));
          };
          // addr_std$10 anycast:(Maybe Anycast) workchain_id:int8 address:bits256
          store_uint(2, 2);
          store_bit(false); // no anycast
          store_byte(addr.workchain);
          store_bytes(addr.hash);
          #Ok(())
        };
      }
    };

    public func build() : Error.WalletResult<Cell> {
      if (bitsBuf.size() > 1023) {
        return #Err(#Internal("TON cell bit length exceeds 1023"));
      };
      if (refsBuf.size() > 4) {
        return #Err(#Internal("TON cell ref count exceeds 4"));
      };
      #Ok({
        bits = Buffer.toArray(bitsBuf);
        refs = Buffer.toArray(refsBuf);
      })
    };
  };

  public func begin_cell() : CellBuilder { CellBuilder() };

  public func wallet_v4r2_code_cell() : Error.WalletResult<Cell> {
    let boc = switch (decode_hex(TON_WALLET_V4R2_CODE_BOC_HEX)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    parse_boc_single_root(boc)
  };

  public func parse_ton_address(input : Text) : Error.WalletResult<TonAddress> {
    let trimmed = Text.trim(input, #char ' ');
    if (Text.size(trimmed) == 0) {
      return #Err(Error.invalid_input("TON address is required"));
    };
    switch (parse_raw_ton_address(trimmed)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(?addr)) return #Ok(addr);
      case (#Ok(null)) {};
    };
    parse_user_friendly_address(trimmed)
  };

  public func build_comment_body(comment : Text) : Error.WalletResult<Cell> {
    let b = begin_cell();
    b.store_u32(0);
    b.store_string_tail(comment);
    b.build()
  };

  public func wallet_v4r2_data_cell(
    pubkey32 : [Nat8],
    wallet_id : Nat32,
  ) : Error.WalletResult<Cell> {
    if (pubkey32.size() != 32) {
      return #Err(Error.invalid_input("TON wallet pubkey must be 32 bytes"));
    };
    let b = begin_cell();
    b.store_u32(0); // seqno
    b.store_u32(wallet_id);
    b.store_bytes(pubkey32);
    b.store_bit(false); // empty plugins dict
    b.build()
  };

  public func state_init_cell(code : Cell, data : Cell) : Error.WalletResult<Cell> {
    let b = begin_cell();
    b.store_bit(false); // split_depth none
    b.store_bit(false); // special none
    b.store_maybe_ref(?code);
    b.store_maybe_ref(?data);
    b.store_bit(false); // library empty HashmapE
    b.build()
  };

  public func contract_address_from_state_init(state_init : Cell, workchain : Nat8) : TonAddress {
    {
      workchain;
      hash = cell_hash(state_init);
      bounceable = null;
      test_only = false;
    }
  };

  public func format_user_friendly_address(
    address : TonAddress,
    bounceable : Bool,
    test_only : Bool,
  ) : Text {
    let payload = Array.init<Nat8>(36, 0);
    var tag : Nat = if (bounceable) 0x11 else 0x51;
    if (test_only) { tag += 0x80 };
    payload[0] := Nat8.fromNat(tag);
    payload[1] := address.workchain;
    var i : Nat = 0;
    while (i < 32 and i < address.hash.size()) {
      payload[i + 2] := address.hash[i];
      i += 1;
    };
    let crc = crc16_xmodem(slice_bytes(Array.freeze(payload), 0, 34));
    payload[34] := Nat8.fromNat((crc / 256) % 256);
    payload[35] := Nat8.fromNat(crc % 256);
    base64_encode_url_nopad(Array.freeze(payload))
  };

  public func format_raw_ton_address(address : TonAddress) : Text {
    raw_workchain_text(address.workchain) # ":" # hex_encode(address.hash)
  };

  public func build_internal_message(
    dest : TonAddress,
    amount_nanotons : Nat,
    bounce : Bool,
    body : ?Cell,
  ) : Error.WalletResult<Cell> {
    let b = begin_cell();
    // int_msg_info$0 ihr_disabled:Bool bounce:Bool bounced:Bool src:MsgAddress ...
    b.store_bit(false); // tag = int_msg_info$0
    b.store_bit(true); // ihr_disabled
    b.store_bit(bounce);
    b.store_bit(false); // bounced
    switch (b.store_msg_address(null)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (b.store_msg_address(?dest)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (b.store_coins(amount_nanotons)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    b.store_bit(false); // extra currencies dict empty
    switch (b.store_coins(0)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} }; // ihr_fee
    switch (b.store_coins(0)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} }; // fwd_fee
    b.store_u64(0); // created_lt
    b.store_u32(0); // created_at
    b.store_bit(false); // init none
    switch (body) {
      case (?bodyCell) {
        b.store_bit(true); // body in ref
        b.store_ref(bodyCell);
      };
      case null {
        b.store_bit(false); // inline empty body
      };
    };
    b.build()
  };

  public func build_jetton_transfer_body(
    amount_units : Nat,
    destination_owner : TonAddress,
    response_destination : TonAddress,
    forward_ton_amount : Nat,
    memo : ?Text,
  ) : Error.WalletResult<Cell> {
    let b = begin_cell();
    b.store_u32(TON_JETTON_OP_TRANSFER);
    b.store_u64(0); // query_id
    switch (b.store_coins(amount_units)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (b.store_msg_address(?destination_owner)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (b.store_msg_address(?response_destination)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    b.store_bit(false); // custom_payload: none
    switch (b.store_coins(forward_ton_amount)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    let forwardPayload = switch (memo) {
      case (?m0) {
        let m = Text.trim(m0, #char ' ');
        if (Text.size(m) == 0) {
          switch (begin_cell().build()) {
            case (#Err(err)) return #Err(err);
            case (#Ok(c)) c;
          }
        } else {
          switch (build_comment_body(m)) {
            case (#Err(err)) return #Err(err);
            case (#Ok(c)) c;
          }
        }
      };
      case null {
        switch (begin_cell().build()) {
          case (#Err(err)) return #Err(err);
          case (#Ok(c)) c;
        }
      };
    };
    b.store_bit(true); // forward_payload in ref
    b.store_ref(forwardPayload);
    b.build()
  };

  public func build_wallet_v4r2_signing_body(
    wallet_id : Nat32,
    valid_until : Nat32,
    seqno : Nat32,
    mode : Nat8,
    out_msg : Cell,
  ) : Error.WalletResult<Cell> {
    let b = begin_cell();
    b.store_u32(wallet_id);
    b.store_u32(valid_until);
    b.store_u32(seqno);
    b.store_u32(0); // opcode = 0 (simple send)
    b.store_uint(Nat8.toNat(mode), 8);
    b.store_ref(out_msg);
    b.build()
  };

  public func build_wallet_v4r2_body_with_signature(
    signature64 : [Nat8],
    signing_body : Cell,
  ) : Error.WalletResult<Cell> {
    if (signature64.size() != 64) {
      return #Err(Error.invalid_input("TON wallet signature must be 64 bytes"));
    };
    let b = begin_cell();
    b.store_bytes(signature64);
    b.store_bits(signing_body.bits);
    for (r in signing_body.refs.vals()) {
      b.store_ref(r);
    };
    b.build()
  };

  public func build_external_message(
    wallet_address : TonAddress,
    body : Cell,
    state_init : ?Cell,
  ) : Error.WalletResult<Cell> {
    let b = begin_cell();
    // ext_in_msg_info$10 src:MsgAddressExt dest:MsgAddressInt import_fee:Grams
    b.store_uint(2, 2);
    switch (b.store_msg_address(null)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (b.store_msg_address(?wallet_address)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (b.store_coins(0)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (state_init) {
      case (?init) {
        b.store_bit(true); // init exists
        b.store_bit(true); // init as ref
        b.store_ref(init);
      };
      case null {
        b.store_bit(false); // no init
      };
    };
    b.store_bit(true); // body as ref
    b.store_ref(body);
    b.build()
  };

  public func cell_hash(cell : Cell) : [Nat8] {
    let repr = Buffer.Buffer<Nat8>(128);
    repr.add(cell_descriptor_1(cell));
    repr.add(cell_descriptor_2(cell.bits.size()));
    append_bytes(repr, bits_to_padded_bytes(cell.bits));

    for (r in cell.refs.vals()) {
      let depth = cell_depth(r);
      repr.add(Nat8.fromNat((depth / 256) % 256));
      repr.add(Nat8.fromNat(depth % 256));
    };
    for (r in cell.refs.vals()) {
      append_bytes(repr, cell_hash(r));
    };

    Blob.toArray(SHA256.fromArray(#sha256, Buffer.toArray(repr)))
  };

  public func cell_to_boc_bytes(cell : Cell) : Error.WalletResult<[Nat8]> {
    let flatBuf = Buffer.Buffer<FlatCell>(8);
    let root_idx = flatten_cell_postorder(cell, flatBuf);
    let flat = Buffer.toArray(flatBuf);

    let cells_data = switch (serialize_cells_data(flat)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let cells_num = flat.size();
    let roots_num : Nat = 1;
    let absent_num : Nat = 0;
    let total_cells_size = cells_data.size();

    let size_bytes = minimal_be_bytes_len(if (cells_num > 0) cells_num - 1 else 1);
    let offset_bytes = minimal_be_bytes_len(if (total_cells_size > 0) total_cells_size else 1);

    let out = Buffer.Buffer<Nat8>(32 + cells_data.size());
    append_bytes(out, [0xb5, 0xee, 0x9c, 0x72]);
    let flags = Nat8.fromNat(size_bytes % 8); // no idx, no crc32, no cache bits
    out.add(flags);
    out.add(Nat8.fromNat(offset_bytes % 256));
    switch (write_be_var(out, cells_num, size_bytes)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} };
    switch (write_be_var(out, roots_num, size_bytes)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} };
    switch (write_be_var(out, absent_num, size_bytes)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} };
    switch (write_be_var(out, total_cells_size, offset_bytes)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} };
    switch (write_be_var(out, root_idx, size_bytes)) { case (#Err(err)) return #Err(err); case (#Ok(())) {} };
    append_bytes(out, cells_data);
    #Ok(Buffer.toArray(out))
  };

  public func cell_to_boc_base64(cell : Cell) : Error.WalletResult<Text> {
    switch (cell_to_boc_bytes(cell)) {
      case (#Err(err)) #Err(err);
      case (#Ok(bytes)) #Ok(base64_encode_std_nopad(bytes));
    }
  };

  public func parse_boc_single_root(bytes : [Nat8]) : Error.WalletResult<Cell> {
    if (bytes.size() < 8) {
      return #Err(Error.invalid_input("invalid TON BOC magic"));
    };
    if (
      bytes[0] != 0xb5 or bytes[1] != 0xee or bytes[2] != 0x9c or bytes[3] != 0x72
    ) {
      return #Err(Error.invalid_input("invalid TON BOC magic"));
    };
    let flags = bytes[4];
    let has_idx = (Nat8.toNat(flags) / 128) % 2 == 1;
    let has_crc32 = (Nat8.toNat(flags) / 64) % 2 == 1;
    let size_bytes = Nat8.toNat(flags % 8);
    if (size_bytes == 0 or size_bytes > 8) {
      return #Err(Error.invalid_input("invalid TON BOC size bytes"));
    };
    let offset_bytes = Nat8.toNat(bytes[5]);
    if (offset_bytes == 0 or offset_bytes > 8) {
      return #Err(Error.invalid_input("invalid TON BOC offset bytes"));
    };

    var p : Nat = 6;
    let cells_num = switch (read_be_var(bytes, p, size_bytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) { p := v.next; v.value };
    };
    let roots_num = switch (read_be_var(bytes, p, size_bytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) { p := v.next; v.value };
    };
    ignore switch (read_be_var(bytes, p, size_bytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) { p := v.next; v.value };
    };
    let total_cells_size = switch (read_be_var(bytes, p, offset_bytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) { p := v.next; v.value };
    };
    if (roots_num != 1) {
      return #Err(Error.invalid_input("only single-root TON BOC is supported"));
    };
    let root_index = switch (read_be_var(bytes, p, size_bytes)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) { p := v.next; v.value };
    };
    if (root_index >= cells_num) {
      return #Err(Error.invalid_input("TON BOC root index out of range"));
    };

    if (has_idx) {
      let skip = cells_num * offset_bytes;
      if (p + skip > bytes.size()) {
        return #Err(Error.invalid_input("TON BOC truncated index table"));
      };
      p += skip;
    };

    let data_start = p;
    let data_end = data_start + total_cells_size;
    if (data_end > bytes.size()) {
      return #Err(Error.invalid_input("TON BOC truncated cells data"));
    };

    let parsedBuf = Buffer.Buffer<ParsedCell>(cells_num);
    while (p < data_end and parsedBuf.size() < cells_num) {
      if (p + 2 > data_end) {
        return #Err(Error.invalid_input("TON BOC truncated cell descriptor"));
      };
      let d1 = bytes[p];
      let d2 = bytes[p + 1];
      p += 2;

      let refs_count = Nat8.toNat(d1 % 8);
      let exotic = (Nat8.toNat(d1) / 8) % 2 == 1;
      let level = Nat8.toNat(d1) / 32;
      if (exotic) {
        return #Err(Error.invalid_input("TON exotic cells are not supported in parser"));
      };
      if (level != 0) {
        return #Err(Error.invalid_input("TON non-zero level cells are not supported in parser"));
      };

      let full_bytes = Nat8.toNat(d2 / 2);
      let has_partial = Nat8.toNat(d2 % 2) == 1;
      let data_bytes_len = full_bytes + (if (has_partial) 1 else 0);
      if (p + data_bytes_len > data_end) {
        return #Err(Error.invalid_input("TON BOC truncated cell data"));
      };
      let dataSlice = slice_bytes(bytes, p, p + data_bytes_len);
      p += data_bytes_len;
      let bits = switch (unpadded_bytes_to_bits(dataSlice, full_bytes, has_partial)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };

      let refsBuf = Buffer.Buffer<Nat>(refs_count);
      var j : Nat = 0;
      while (j < refs_count) {
        let idx = switch (read_be_var(bytes, p, size_bytes)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) { p := v.next; v.value };
        };
        refsBuf.add(idx);
        j += 1;
      };
      parsedBuf.add({ bits; refs = Buffer.toArray(refsBuf) });
    };

    if (parsedBuf.size() != cells_num or p != data_end) {
      return #Err(Error.invalid_input("TON BOC cells section parse mismatch"));
    };
    if (has_crc32 and data_end + 4 > bytes.size()) {
      return #Err(Error.invalid_input("TON BOC truncated crc32"));
    };

    let parsed = Buffer.toArray(parsedBuf);
    let memo = Array.init<?Cell>(parsed.size(), null);
    build_parsed_cell(root_index, parsed, memo)
  };

  func build_parsed_cell(
    idx : Nat,
    parsed : [ParsedCell],
    memo : [var ?Cell],
  ) : Error.WalletResult<Cell> {
    if (idx >= parsed.size()) {
      return #Err(Error.invalid_input("TON BOC ref out of range"));
    };
    switch (memo[idx]) {
      case (?cell) return #Ok(cell);
      case null {};
    };
    let p = parsed[idx];
    let refsBuf = Buffer.Buffer<Cell>(p.refs.size());
    for (r in p.refs.vals()) {
      let child = switch (build_parsed_cell(r, parsed, memo)) {
        case (#Err(err)) return #Err(err);
        case (#Ok(v)) v;
      };
      refsBuf.add(child);
    };
    let cell : Cell = {
      bits = p.bits;
      refs = Buffer.toArray(refsBuf);
    };
    memo[idx] := ?cell;
    #Ok(cell)
  };

  func flatten_cell_postorder(cell : Cell, flat : Buffer.Buffer<FlatCell>) : Nat {
    let refIds = Buffer.Buffer<Nat>(cell.refs.size());
    for (r in cell.refs.vals()) {
      refIds.add(flatten_cell_postorder(r, flat));
    };
    let idx = flat.size();
    flat.add({
      bits = cell.bits;
      refs = Buffer.toArray(refIds);
    });
    idx
  };

  func serialize_cells_data(flat : [FlatCell]) : Error.WalletResult<[Nat8]> {
    let size_bytes = minimal_be_bytes_len(if (flat.size() > 0) flat.size() - 1 else 1);
    let out = Buffer.Buffer<Nat8>(256);
    for (cell in flat.vals()) {
      if (cell.refs.size() > 4) {
        return #Err(#Internal("TON BOC serialize: refs > 4"));
      };
      out.add(Nat8.fromNat(cell.refs.size() % 8)); // ordinary, level 0
      out.add(cell_descriptor_2(cell.bits.size()));
      append_bytes(out, bits_to_padded_bytes(cell.bits));
      for (r in cell.refs.vals()) {
        switch (write_be_var(out, r, size_bytes)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(())) {};
        }
      };
    };
    #Ok(Buffer.toArray(out))
  };

  func minimal_be_bytes_len(value0 : Nat) : Nat {
    var value = value0;
    var width : Nat = 1;
    while (value > 255) {
      value /= 256;
      width += 1;
    };
    width
  };

  func write_be_var(
    out : Buffer.Buffer<Nat8>,
    value : Nat,
    width : Nat,
  ) : Error.WalletResult<()> {
    if (width == 0 or width > 8) {
      return #Err(#Internal("invalid write_be_var width"));
    };
    let max : Nat = pow256(width) - 1;
    if (value > max) {
      return #Err(#Internal("value does not fit in requested byte width"));
    };
    var i : Nat = width;
    while (i > 0) {
      i -= 1;
      let div = pow256(i);
      out.add(Nat8.fromNat((value / div) % 256));
    };
    #Ok(())
  };

  func read_be_var(
    bytes : [Nat8],
    p : Nat,
    width : Nat,
  ) : Error.WalletResult<{ value : Nat; next : Nat }> {
    if (width == 0 or width > 8) {
      return #Err(#Internal("invalid read_be_var width"));
    };
    if (p + width > bytes.size()) {
      return #Err(Error.invalid_input("TON BOC truncated integer"));
    };
    var out : Nat = 0;
    var i : Nat = 0;
    while (i < width) {
      out := (out * 256) + Nat8.toNat(bytes[p + i]);
      i += 1;
    };
    #Ok({ value = out; next = p + width })
  };

  func unpadded_bytes_to_bits(
    data : [Nat8],
    full_bytes : Nat,
    has_partial : Bool,
  ) : Error.WalletResult<[Bool]> {
    let expected = full_bytes + (if (has_partial) 1 else 0);
    if (data.size() != expected) {
      return #Err(Error.invalid_input("TON cell data length mismatch"));
    };
    let bits = Buffer.Buffer<Bool>(full_bytes * 8 + (if (has_partial) 7 else 0));
    var i : Nat = 0;
    while (i < full_bytes) {
      let b = Nat8.toNat(data[i]);
      var j : Nat = 0;
      while (j < 8) {
        let bit = ((b / pow2(7 - j)) % 2) == 1;
        bits.add(bit);
        j += 1;
      };
      i += 1;
    };
    if (has_partial) {
      let last = Nat8.toNat(data[data.size() - 1]);
      if (last == 0) {
        return #Err(Error.invalid_input("TON partial cell byte has no terminator"));
      };
      var tz : Nat = 0;
      var tmp = last;
      while (tz < 8 and (tmp % 2) == 0) {
        tz += 1;
        tmp /= 2;
      };
      if (tz > 6) {
        return #Err(Error.invalid_input("TON partial cell padding is invalid"));
      };
      let data_bits_in_last = 7 - tz;
      var j2 : Nat = 0;
      while (j2 < data_bits_in_last) {
        let bit = ((last / pow2(7 - j2)) % 2) == 1;
        bits.add(bit);
        j2 += 1;
      };
    };
    #Ok(Buffer.toArray(bits))
  };

  func cell_depth(cell : Cell) : Nat {
    if (cell.refs.size() == 0) return 0;
    var maxDepth : Nat = 0;
    for (r in cell.refs.vals()) {
      let d = cell_depth(r);
      if (d > maxDepth) { maxDepth := d };
    };
    maxDepth + 1
  };

  func cell_descriptor_1(cell : Cell) : Nat8 {
    Nat8.fromNat(cell.refs.size() % 8)
  };

  func cell_descriptor_2(bits_len : Nat) : Nat8 {
    let full_bytes = bits_len / 8;
    let partial = if ((bits_len % 8) == 0) 0 else 1;
    Nat8.fromNat((full_bytes + full_bytes + partial) % 256)
  };

  func bits_to_padded_bytes(bits : [Bool]) : [Nat8] {
    if (bits.size() == 0) return [];
    let out = Buffer.Buffer<Nat8>((bits.size() + 7) / 8);
    var i : Nat = 0;
    while (i < bits.size()) {
      let end = if (i + 8 < bits.size()) i + 8 else bits.size();
      var byte : Nat = 0;
      var j : Nat = i;
      while (j < end) {
        if (bits[j]) {
          byte += pow2(7 - (j - i));
        };
        j += 1;
      };
      if (end - i < 8) {
        byte += pow2(7 - (end - i)); // end-bit padding
      };
      out.add(Nat8.fromNat(byte % 256));
      i += 8;
    };
    Buffer.toArray(out)
  };

  func crc16_xmodem(data : [Nat8]) : Nat {
    var crc : Nat32 = 0;
    for (b in data.vals()) {
      crc := Nat32.bitxor(crc, Nat32.fromNat(Nat8.toNat(b) * 256));
      var i : Nat = 0;
      while (i < 8) {
        if (Nat32.bitand(crc, 0x8000) != 0) {
          crc := Nat32.bitxor(
            Nat32.bitand(Nat32.bitshiftLeft(crc, 1), 0xffff),
            0x1021,
          );
        } else {
          crc := Nat32.bitand(Nat32.bitshiftLeft(crc, 1), 0xffff);
        };
        i += 1;
      };
    };
    Nat32.toNat(crc)
  };

  func base64_encode_url_nopad(data : [Nat8]) : Text {
    base64_encode_nopad(data, BASE64_URL_ALPHABET)
  };

  func base64_encode_std_nopad(data : [Nat8]) : Text {
    base64_encode_nopad(data, BASE64_STD_ALPHABET)
  };

  func base64_encode_nopad(data : [Nat8], alphabet : [Char]) : Text {
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

  func decode_hex(input : Text) : Error.WalletResult<[Nat8]> {
    let s = Text.trim(input, #char ' ');
    if ((Text.size(s) % 2) != 0) {
      return #Err(Error.invalid_input("hex length must be even"));
    };
    let chars = chars_array(s);
    let out = Buffer.Buffer<Nat8>(chars.size() / 2);
    var i : Nat = 0;
    while (i < chars.size()) {
      let hi = switch (hex_digit(chars[i])) {
        case (?v) v;
        case null return #Err(Error.invalid_input("invalid hex character"));
      };
      let lo = switch (hex_digit(chars[i + 1])) {
        case (?v) v;
        case null return #Err(Error.invalid_input("invalid hex character"));
      };
      out.add(Nat8.fromNat((hi * 16) + lo));
      i += 2;
    };
    #Ok(Buffer.toArray(out))
  };

  func parse_raw_ton_address(input : Text) : Error.WalletResult<?TonAddress> {
    let chars = chars_array(input);
    var colonIndex : ?Nat = null;
    var i : Nat = 0;
    while (i < chars.size()) {
      if (chars[i] == ':') {
        colonIndex := ?i;
        i := chars.size();
      } else {
        i += 1;
      }
    };
    let idx = switch (colonIndex) {
      case null return #Ok(null);
      case (?v) v;
    };
    let wcText = Text.trim(sub_text(chars, 0, idx), #char ' ');
    let hashText = Text.trim(sub_text(chars, idx + 1, chars.size()), #char ' ');
    let wcByte = switch (parse_workchain_byte_text(wcText)) {
      case (?v) v;
      case null return #Err(Error.invalid_input("invalid TON raw workchain id"));
    };
    let hashBytes = switch (decode_hex(hashText)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (hashBytes.size() != 32) {
      return #Err(Error.invalid_input("TON raw address hash must be 32 bytes hex"));
    };
    #Ok(?( {
      workchain = wcByte;
      hash = hashBytes;
      bounceable = null;
      test_only = false;
    } ))
  };

  func parse_user_friendly_address(input : Text) : Error.WalletResult<TonAddress> {
    let decoded = switch (base64_decode_url_or_std(input)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (decoded.size() != 36) {
      return #Err(Error.invalid_input("TON user-friendly address must decode to 36 bytes"));
    };
    let crcExpected = (Nat8.toNat(decoded[34]) * 256) + Nat8.toNat(decoded[35]);
    let crcActual = crc16_xmodem(slice_bytes(decoded, 0, 34));
    if (crcExpected != crcActual) {
      return #Err(Error.invalid_input("TON address crc16 mismatch"));
    };
    let tag = Nat8.toNat(decoded[0]);
    let test_only = (tag / 128) % 2 == 1;
    let bounceable = (tag / 64) % 2 == 0;
    let low = tag % 64;
    if (low != 0x11) {
      return #Err(Error.invalid_input("unsupported TON address tag"));
    };
    #Ok({
      workchain = decoded[1];
      hash = slice_bytes(decoded, 2, 34);
      bounceable = ?bounceable;
      test_only;
    })
  };

  func hex_encode(data : [Nat8]) : Text {
    let hexChars : [Char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
    var out = "";
    for (b in data.vals()) {
      let n = Nat8.toNat(b);
      out #= Text.fromChar(hexChars[n / 16]);
      out #= Text.fromChar(hexChars[n % 16]);
    };
    out
  };

  func base64_decode_url_or_std(text : Text) : Error.WalletResult<[Nat8]> {
    let raw = Blob.toArray(Text.encodeUtf8(Text.trim(text, #char ' ')));
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
      let c0 = arr[i];
      let c1 = arr[i + 1];
      let c2 = arr[i + 2];
      let c3 = arr[i + 3];
      let v0 = switch (b64_val(c0)) { case (?v) v; case null return #Err(Error.invalid_input("invalid base64 character")) };
      let v1 = switch (b64_val(c1)) { case (?v) v; case null return #Err(Error.invalid_input("invalid base64 character")) };
      let v2 = if (c2 == 61) 0 else switch (b64_val(c2)) { case (?v) v; case null return #Err(Error.invalid_input("invalid base64 character")) };
      let v3 = if (c3 == 61) 0 else switch (b64_val(c3)) { case (?v) v; case null return #Err(Error.invalid_input("invalid base64 character")) };
      let n = (v0 * 262_144) + (v1 * 4_096) + (v2 * 64) + v3;
      out.add(Nat8.fromNat((n / 65_536) % 256));
      if (c2 != 61) { out.add(Nat8.fromNat((n / 256) % 256)) };
      if (c3 != 61) { out.add(Nat8.fromNat(n % 256)) };
      i += 4;
    };
    #Ok(Buffer.toArray(out))
  };

  func b64_val(c : Nat8) : ?Nat {
    let n = Nat8.toNat(c);
    if (n >= 65 and n <= 90) return ?(n - 65);
    if (n >= 97 and n <= 122) return ?(n - 97 + 26);
    if (n >= 48 and n <= 57) return ?(n - 48 + 52);
    if (n == 43 or n == 45) return ?62; // '+' or '-'
    if (n == 47 or n == 95) return ?63; // '/' or '_'
    if (n == 61) return ?0; // '='
    null
  };

  func hex_digit(c : Char) : ?Nat {
    let n = Char.toNat32(c);
    if (n >= 48 and n <= 57) return ?Nat32.toNat(n - 48);
    if (n >= 65 and n <= 70) return ?Nat32.toNat(n - 55);
    if (n >= 97 and n <= 102) return ?Nat32.toNat(n - 87);
    null
  };

  func chars_array(t : Text) : [Char] {
    let buf = Buffer.Buffer<Char>(Text.size(t));
    for (c in t.chars()) { buf.add(c) };
    Buffer.toArray(buf)
  };

  func slice_bytes(src : [Nat8], start : Nat, endExclusive : Nat) : [Nat8] {
    if (endExclusive <= start or start >= src.size()) return [];
    let end = if (endExclusive > src.size()) src.size() else endExclusive;
    let buf = Buffer.Buffer<Nat8>(end - start);
    var i = start;
    while (i < end) {
      buf.add(src[i]);
      i += 1;
    };
    Buffer.toArray(buf)
  };

  func append_bytes(buf : Buffer.Buffer<Nat8>, bytes : [Nat8]) {
    for (b in bytes.vals()) { buf.add(b) };
  };

  func nat_to_be_bytes(amount : Nat) : [Nat8] {
    if (amount == 0) return [];
    let rev = Buffer.Buffer<Nat8>(16);
    var n = amount;
    while (n > 0) {
      rev.add(Nat8.fromNat(n % 256));
      n /= 256;
    };
    let arr = Buffer.toArray(rev);
    let out = Buffer.Buffer<Nat8>(arr.size());
    var i = arr.size();
    while (i > 0) {
      i -= 1;
      out.add(arr[i]);
    };
    Buffer.toArray(out)
  };

  func sub_text(chars : [Char], start : Nat, endExclusive : Nat) : Text {
    if (endExclusive <= start or start >= chars.size()) return "";
    let end = if (endExclusive > chars.size()) chars.size() else endExclusive;
    var out = "";
    var i = start;
    while (i < end) {
      out #= Text.fromChar(chars[i]);
      i += 1;
    };
    out
  };

  func raw_workchain_text(wcByte : Nat8) : Text {
    let n = Nat8.toNat(wcByte);
    if (n == 255) {
      "-1"
    } else {
      Nat.toText(n)
    }
  };

  func parse_workchain_byte_text(t : Text) : ?Nat8 {
    let s = Text.trim(t, #char ' ');
    if (s == "-1") return ?255;
    if (Text.size(s) == 0) return null;
    let chars = chars_array(s);
    var acc : Nat = 0;
    for (c in chars.vals()) {
      if (c < '0' or c > '9') return null;
      acc := (acc * 10) + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
    };
    if (acc > 127) return null;
    ?Nat8.fromNat(acc)
  };

  func pow2(n : Nat) : Nat {
    var out : Nat = 1;
    var i : Nat = 0;
    while (i < n) {
      out *= 2;
      i += 1;
    };
    out
  };

  func pow256(n : Nat) : Nat {
    var out : Nat = 1;
    var i : Nat = 0;
    while (i < n) {
      out *= 256;
      i += 1;
    };
    out
  };
}

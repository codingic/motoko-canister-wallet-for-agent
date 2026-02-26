import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import AppConfig "./config/app_config";
import WalletError "./error";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.INTERNET_COMPUTER;
  let ICP_DECIMALS : Nat8 = 8;

  public type IcrcAccount = {
    owner : Principal;
    subaccount : ?Blob;
  };

  public type IcrcTransferArg = {
    from_subaccount : ?Blob;
    to : IcrcAccount;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
    amount : Nat;
  };

  public type IcrcTransferError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  };

  type IcrcLedger = actor {
    icrc1_balance_of : shared query (IcrcAccount) -> async Nat;
    icrc1_decimals : shared query () -> async Nat8;
    icrc1_symbol : shared query () -> async Text;
    icrc1_name : shared query () -> async Text;
    icrc1_transfer : shared (IcrcTransferArg) -> async { #Ok : Nat; #Err : IcrcTransferError };
  };

  public func get_balance_icp(req : Types.BalanceRequest) : async WalletError.WalletResult<Types.BalanceResponse> {
    switch (validate_account_text(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    if (non_empty_opt_text(req.token) != null) {
      return #Err(#InvalidInput("internet_computer_get_balance_icp does not accept token parameter"));
    };

    let ledger = icp_ledger_principal();
    let account = switch (parse_icrc_account(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_icrc_decimals(ledger)) {
      case (#Ok(v)) v;
      case (#Err(_)) ICP_DECIMALS;
    };
    let amount = switch (await icrc1_balance_of(ledger, account)) {
      case (#Ok(v)) v;
      case (#Err(err)) return #Err(err);
    };

    #Ok({
      network = NETWORK_NAME;
      account = req.account;
      token = null;
      amount = ?format_nat_units(amount, decimals);
      decimals = ?decimals;
      block_ref = null;
      pending = false;
      message = ?"icrc1_balance_of on ICP ledger";
    })
  };

  public func get_balance_icrc(req : Types.BalanceRequest) : async WalletError.WalletResult<Types.BalanceResponse> {
    switch (validate_account_text(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };

    let token_text = switch (non_empty_opt_text(req.token)) {
      case (?t) t;
      case null return #Err(#InvalidInput("token ledger canister id is required"));
    };
    let ledger = switch (parse_principal_text(token_text, "token ledger canister id")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let account = switch (parse_icrc_account(req.account)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_icrc_decimals(ledger)) {
      case (#Ok(v)) v;
      case (#Err(err)) return #Err(err);
    };
    let amount = switch (await icrc1_balance_of(ledger, account)) {
      case (#Ok(v)) v;
      case (#Err(err)) return #Err(err);
    };

    #Ok({
      network = NETWORK_NAME;
      account = req.account;
      token = ?token_text;
      amount = ?format_nat_units(amount, decimals);
      decimals = ?decimals;
      block_ref = null;
      pending = false;
      message = ?"icrc1_balance_of on token ledger";
    })
  };

  public func transfer_icp(req : Types.TransferRequest) : async WalletError.WalletResult<Types.TransferResponse> {
    switch (validate_transfer_basics(req)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    if (non_empty_opt_text(req.token) != null) {
      return #Err(#InvalidInput("internet_computer_transfer_icp does not accept token parameter"));
    };

    let ledger = icp_ledger_principal();
    let to = switch (parse_icrc_account(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_icrc_decimals(ledger)) {
      case (#Ok(v)) v;
      case (#Err(_)) ICP_DECIMALS;
    };
    let amount = switch (parse_decimal_nat_units(req.amount, decimals)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    // TODO(parity): validate `from` equals current canister principal (Rust version enforces this).
    switch (validate_from_if_present(req.from)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };

    let block_index = switch (
      await icrc1_transfer(
        ledger,
        {
          from_subaccount = null;
          to;
          fee = null;
          memo = parse_memo(req.memo);
          created_at_time = null;
          amount;
        },
      )
    ) {
      case (#Ok(v)) v;
      case (#Err(err)) return #Err(err);
    };

    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = ?Nat.toText(block_index);
      message = "icrc1_transfer on ICP ledger accepted";
    })
  };

  public func transfer_icrc(req : Types.TransferRequest) : async WalletError.WalletResult<Types.TransferResponse> {
    switch (validate_transfer_basics(req)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    let token_text = switch (non_empty_opt_text(req.token)) {
      case (?t) t;
      case null return #Err(#InvalidInput("token ledger canister id is required"));
    };
    let ledger = switch (parse_principal_text(token_text, "token ledger canister id")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let to = switch (parse_icrc_account(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_icrc_decimals(ledger)) {
      case (#Ok(v)) v;
      case (#Err(err)) return #Err(err);
    };
    let amount = switch (parse_decimal_nat_units(req.amount, decimals)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    // TODO(parity): validate `from` equals current canister principal (Rust version enforces this).
    switch (validate_from_if_present(req.from)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };

    let block_index = switch (
      await icrc1_transfer(
        ledger,
        {
          from_subaccount = null;
          to;
          fee = null;
          memo = parse_memo(req.memo);
          created_at_time = null;
          amount;
        },
      )
    ) {
      case (#Ok(v)) v;
      case (#Err(err)) return #Err(err);
    };

    #Ok({
      network = NETWORK_NAME;
      accepted = true;
      tx_id = ?Nat.toText(block_index);
      message = "icrc1_transfer on token ledger accepted";
    })
  };

  public func discover_icrc_token(ledger_text : Text) : async WalletError.WalletResult<Types.ConfiguredTokenResponse> {
    let ledger = switch (parse_principal_text(ledger_text, "token ledger canister id")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_icrc_decimals(ledger)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let symbol = switch (await fetch_icrc_symbol(ledger)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let name = switch (await fetch_icrc_name(ledger)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok({
      network = NETWORK_NAME;
      symbol = trim_ascii_ws(symbol);
      name = trim_ascii_ws(name);
      token_address = Principal.toText(ledger);
      decimals = Nat8.toNat(decimals);
    })
  };

  func icp_ledger_principal() : Principal {
    if (AppConfig.default_icp_ledger_use_mainnet()) {
      AppConfig.icp_ledger_mainnet_principal();
    } else {
      AppConfig.icp_ledger_local_principal();
    }
  };

  func validate_account_text(account : Text) : WalletError.WalletResult<()> {
    if (trim_ascii_ws(account) == "") {
      #Err(#InvalidInput("account is required"));
    } else {
      #Ok(());
    }
  };

  func validate_transfer_basics(req : Types.TransferRequest) : WalletError.WalletResult<()> {
    if (trim_ascii_ws(req.to) == "") {
      return #Err(#InvalidInput("to is required"));
    };
    if (trim_ascii_ws(req.amount) == "") {
      return #Err(#InvalidInput("amount is required"));
    };
    #Ok(())
  };

  func validate_from_if_present(from : ?Text) : WalletError.WalletResult<()> {
    switch (non_empty_opt_text(from)) {
      case null #Ok(());
      case (?from_text) {
        switch (parse_principal_text(from_text, "from principal")) {
          case (#Ok(_)) #Ok(());
          case (#Err(err)) #Err(err);
        };
      };
    }
  };

  func parse_icrc_account(text : Text) : WalletError.WalletResult<IcrcAccount> {
    switch (parse_principal_text(text, "account principal")) {
      case (#Err(err)) #Err(err);
      case (#Ok(owner)) #Ok({ owner; subaccount = null });
    }
  };

  func parse_principal_text(text : Text, field_name : Text) : WalletError.WalletResult<Principal> {
    ignore field_name;
    let t = trim_ascii_ws(text);
    if (t == "") {
      return #Err(#InvalidInput("principal text is required"));
    };
    // NOTE: `Principal.fromText` traps on invalid input; Rust version returns a typed error.
    // We keep behavior close enough for now and will replace with explicit parser later.
    #Ok(Principal.fromText(t))
  };

  func parse_memo(memo : ?Text) : ?Blob {
    switch (non_empty_opt_text(memo)) {
      case null null;
      case (?m) ?Text.encodeUtf8(m);
    }
  };

  func non_empty_opt_text(value : ?Text) : ?Text {
    switch (value) {
      case null null;
      case (?v) {
        let t = trim_ascii_ws(v);
        if (t == "") null else ?t
      };
    }
  };

  func ledger_actor(ledger : Principal) : IcrcLedger {
    actor (Principal.toText(ledger)) : IcrcLedger
  };

  func icrc1_balance_of(
    ledger : Principal,
    account : IcrcAccount,
  ) : async WalletError.WalletResult<Nat> {
    let a = ledger_actor(ledger);
    try {
      #Ok(await a.icrc1_balance_of(account))
    } catch e {
      #Err(#Internal("icrc1_balance_of failed: " # Error.message(e)))
    }
  };

  func fetch_icrc_decimals(ledger : Principal) : async WalletError.WalletResult<Nat8> {
    let a = ledger_actor(ledger);
    try {
      #Ok(await a.icrc1_decimals())
    } catch e {
      #Err(#Internal("icrc1_decimals failed: " # Error.message(e)))
    }
  };

  func fetch_icrc_symbol(ledger : Principal) : async WalletError.WalletResult<Text> {
    let a = ledger_actor(ledger);
    try {
      #Ok(await a.icrc1_symbol())
    } catch e {
      #Err(#Internal("icrc1_symbol failed: " # Error.message(e)))
    }
  };

  func fetch_icrc_name(ledger : Principal) : async WalletError.WalletResult<Text> {
    let a = ledger_actor(ledger);
    try {
      #Ok(await a.icrc1_name())
    } catch e {
      #Err(#Internal("icrc1_name failed: " # Error.message(e)))
    }
  };

  func icrc1_transfer(
    ledger : Principal,
    arg : IcrcTransferArg,
  ) : async WalletError.WalletResult<Nat> {
    let a = ledger_actor(ledger);
    try {
      switch (await a.icrc1_transfer(arg)) {
        case (#Ok(v)) #Ok(v);
        case (#Err(err)) #Err(#Internal("icrc1_transfer rejected: " # describe_transfer_error(err)));
      }
    } catch e {
      #Err(#Internal("icrc1_transfer call failed: " # Error.message(e)))
    }
  };

  func describe_transfer_error(err : IcrcTransferError) : Text {
    switch (err) {
      case (#BadFee({ expected_fee })) "BadFee expected_fee=" # Nat.toText(expected_fee);
      case (#BadBurn({ min_burn_amount })) "BadBurn min_burn_amount=" # Nat.toText(min_burn_amount);
      case (#InsufficientFunds({ balance })) "InsufficientFunds balance=" # Nat.toText(balance);
      case (#TooOld) "TooOld";
      case (#CreatedInFuture({ ledger_time })) "CreatedInFuture ledger_time=" # Nat64.toText(ledger_time);
      case (#Duplicate({ duplicate_of })) "Duplicate duplicate_of=" # Nat.toText(duplicate_of);
      case (#TemporarilyUnavailable) "TemporarilyUnavailable";
      case (#GenericError({ error_code; message })) {
        "GenericError code=" # Nat.toText(error_code) # " message=" # message
      };
    }
  };

  func format_nat_units(value : Nat, decimals : Nat8) : Text {
    let digits = normalize_numeric_separators(Nat.toText(value));
    if (decimals == 0) return digits;

    let d = Nat8.toNat(decimals);
    if (digits == "0") return "0";

    let chars = Text.toArray(digits);
    if (chars.size() <= d) {
      let pad = d - chars.size();
      let fracBuf = Array.tabulate<Char>(pad, func(_i) = '0');
      let fracAll = Array.append<Char>(fracBuf, chars);
      let fracTrimmed = trim_trailing_zeros(fracAll);
      if (fracTrimmed.size() == 0) {
        "0"
      } else {
        "0." # Text.fromArray(fracTrimmed)
      }
    } else {
      let split = chars.size() - d;
      let whole = Array.tabulate<Char>(split, func(i) = chars[i]);
      let frac = Array.tabulate<Char>(chars.size() - split, func(i) = chars[split + i]);
      let fracTrimmed = trim_trailing_zeros(frac);
      if (fracTrimmed.size() == 0) {
        Text.fromArray(whole)
      } else {
        Text.fromArray(whole) # "." # Text.fromArray(fracTrimmed)
      }
    }
  };

  func parse_decimal_nat_units(value : Text, decimals : Nat8) : WalletError.WalletResult<Nat> {
    let v = trim_ascii_ws(value);
    if (v == "") return #Err(#InvalidInput("amount is required"));
    if (Text.startsWith(v, #char '-')) return #Err(#InvalidInput("amount must be positive"));

    let parts = Iter.toArray(Text.split(v, #char '.'));
    if (parts.size() > 2) return #Err(#InvalidInput("amount format is invalid"));

    let wholeText = normalize_numeric_separators(parts[0]);
    if (wholeText != "" and not all_ascii_digits(wholeText)) {
      return #Err(#InvalidInput("amount must be decimal"));
    };

    let wholeNum = if (wholeText == "") {
      0
    } else {
      switch (Nat.fromText(wholeText)) {
        case (?n) n;
        case null return #Err(#InvalidInput("amount parse failed"));
      }
    };

    let scale = Nat.pow(10, Nat8.toNat(decimals));
    var total = wholeNum * scale;

    if (parts.size() == 2) {
      let fracPart = normalize_numeric_separators(parts[1]);
      if (not all_ascii_digits(fracPart)) {
        return #Err(#InvalidInput("amount must be decimal"));
      };
      if (Text.size(fracPart) > Nat8.toNat(decimals)) {
        return #Err(#InvalidInput("too many decimal places"));
      };

      let fracChars = Text.toArray(fracPart);
      let paddedFrac = Array.append<Char>(
        fracChars,
        Array.tabulate<Char>(Nat8.toNat(decimals) - fracChars.size(), func(_i) = '0'),
      );
      if (paddedFrac.size() > 0) {
        switch (Nat.fromText(Text.fromArray(paddedFrac))) {
          case (?n) { total += n };
          case null return #Err(#InvalidInput("amount parse failed"));
        };
      };
    };

    #Ok(total)
  };

  func normalize_numeric_separators(value : Text) : Text {
    let trimmed = trim_ascii_ws(value);
    let buf = Array.filter<Char>(
      Text.toArray(trimmed),
      func(c) = c != '_' and c != ',',
    );
    Text.fromArray(buf)
  };

  func trim_trailing_zeros(chars : [Char]) : [Char] {
    var end = chars.size();
    while (end > 0 and chars[end - 1] == '0') {
      end -= 1;
    };
    Array.tabulate<Char>(end, func(i) = chars[i])
  };

  func all_ascii_digits(t : Text) : Bool {
    for (c in t.chars()) {
      if (not Char.isDigit(c)) return false;
    };
    true
  };

  func trim_ascii_ws(t : Text) : Text {
    Text.trim(t, #predicate(func(c) = Char.isWhitespace(c)))
  };
}

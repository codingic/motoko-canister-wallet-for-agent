import Principal "mo:base/Principal";

module {
  public type AppMode = {
    #Dev;
    #Prod;
  };

  public let MODE : AppMode = #Dev;

  public let ICP_LEDGER_MAINNET_PRINCIPAL_TEXT : Text = "ryjl3-tyaaa-aaaaa-aaaba-cai";
  public let ICP_LEDGER_LOCAL_PRINCIPAL_TEXT : Text = "xjaw7-xp777-77774-qaajq-cai";

  public func is_dev_mode() : Bool {
    switch (MODE) {
      case (#Dev) true;
      case (#Prod) false;
    };
  };

  public func auth_enabled() : Bool {
    not is_dev_mode();
  };

  public func icp_ledger_mainnet_principal() : Principal {
    Principal.fromText(ICP_LEDGER_MAINNET_PRINCIPAL_TEXT);
  };

  public func icp_ledger_local_principal() : Principal {
    Principal.fromText(ICP_LEDGER_LOCAL_PRINCIPAL_TEXT);
  };

  public func default_icp_ledger_use_mainnet() : Bool {
    switch (MODE) {
      case (#Prod) true;
      case (#Dev) false;
    };
  };

  public func default_http_cycles() : Nat {
    // Base floor for canister-http attached cycles. Final amount is scaled in outcall.mo
    // by max_response_bytes. Keep the floor modest to avoid burst exhaustion when the UI
    // triggers multiple parallel RPCs on initial load.
    50_000_000_000;
  };

  public func default_ecdsa_key_name() : Text {
    switch (MODE) {
      case (#Dev) "dfx_test_key";
      case (#Prod) "key_1";
    };
  };

  public func default_schnorr_key_name() : Text {
    switch (MODE) {
      case (#Dev) "test_key_1";
      case (#Prod) "key_1";
    };
  };
}

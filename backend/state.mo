import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Types "./types";

module {
  public type TokenKey = {
    network : Text;
    token_address : Text;
  };

  public type State = {
    owner : ?Principal;
    paused : Bool;
    custom_tokens : [Types.ConfiguredTokenResponse];
    removed_tokens : [TokenKey];
    runtime_rpcs : [Types.ConfiguredRpcResponse];
  };

  public func default() : State {
    {
      owner = null;
      paused = false;
      custom_tokens = [];
      removed_tokens = [];
      runtime_rpcs = [];
    };
  };

  public func init_owner(state : State, owner : Principal) : State {
    {
      owner = ?owner;
      paused = state.paused;
      custom_tokens = state.custom_tokens;
      removed_tokens = state.removed_tokens;
      runtime_rpcs = state.runtime_rpcs;
    };
  };

  public func owner(state : State) : ?Principal { state.owner };

  public func rotate_owner(state : State, new_owner : Principal) : (?Principal, State) {
    (
      state.owner,
      {
        owner = ?new_owner;
        paused = state.paused;
        custom_tokens = state.custom_tokens;
        removed_tokens = state.removed_tokens;
        runtime_rpcs = state.runtime_rpcs;
      },
    );
  };

  public func is_paused(state : State) : Bool { state.paused };

  public func set_paused(state : State, paused : Bool) : State {
    {
      owner = state.owner;
      paused;
      custom_tokens = state.custom_tokens;
      removed_tokens = state.removed_tokens;
      runtime_rpcs = state.runtime_rpcs;
    };
  };

  public func snapshot(state : State) : State { state };

  public func restore(snapshot : State) : State { snapshot };

  public func custom_tokens_for_network(state : State, network : Text) : [Types.ConfiguredTokenResponse] {
    let out = Buffer.Buffer<Types.ConfiguredTokenResponse>(state.custom_tokens.size());
    for (t in state.custom_tokens.vals()) {
      if (t.network == network) {
        out.add(t);
      };
    };
    Buffer.toArray(out)
  };

  public func removed_tokens(state : State) : [TokenKey] {
    state.removed_tokens
  };

  public func upsert_custom_token(state : State, token : Types.ConfiguredTokenResponse) : (Bool, State) {
    let custom = Buffer.Buffer<Types.ConfiguredTokenResponse>(state.custom_tokens.size() + 1);
    var replaced = false;
    for (t in state.custom_tokens.vals()) {
      if (token_key_eq(t.network, t.token_address, token.network, token.token_address)) {
        custom.add(token);
        replaced := true;
      } else {
        custom.add(t);
      };
    };
    if (not replaced) {
      custom.add(token);
    };

    let removed = Buffer.Buffer<TokenKey>(state.removed_tokens.size());
    for (k in state.removed_tokens.vals()) {
      if (not token_key_eq(k.network, k.token_address, token.network, token.token_address)) {
        removed.add(k);
      };
    };

    (
      replaced,
      {
        owner = state.owner;
        paused = state.paused;
        custom_tokens = Buffer.toArray(custom);
        removed_tokens = Buffer.toArray(removed);
        runtime_rpcs = state.runtime_rpcs;
      },
    )
  };

  public func remove_token(state : State, network : Text, token_address : Text) : (Bool, State) {
    let custom = Buffer.Buffer<Types.ConfiguredTokenResponse>(state.custom_tokens.size());
    var customRemoved = false;
    for (t in state.custom_tokens.vals()) {
      if (token_key_eq(t.network, t.token_address, network, token_address)) {
        customRemoved := true;
      } else {
        custom.add(t);
      };
    };

    var alreadyTombstoned = false;
    for (k in state.removed_tokens.vals()) {
      if (token_key_eq(k.network, k.token_address, network, token_address)) {
        alreadyTombstoned := true;
      };
    };

    let removed = Buffer.Buffer<TokenKey>(state.removed_tokens.size() + 1);
    for (k in state.removed_tokens.vals()) { removed.add(k) };
    if (not alreadyTombstoned) {
      removed.add({ network; token_address });
    };

    let changed = customRemoved or (not alreadyTombstoned);
    (
      changed,
      {
        owner = state.owner;
        paused = state.paused;
        custom_tokens = Buffer.toArray(custom);
        removed_tokens = Buffer.toArray(removed);
        runtime_rpcs = state.runtime_rpcs;
      },
    )
  };

  public func is_removed_token(state : State, network : Text, token_address : Text) : Bool {
    for (k in state.removed_tokens.vals()) {
      if (token_key_eq(k.network, k.token_address, network, token_address)) {
        return true;
      };
    };
    false
  };

  public func configured_rpcs(state : State) : [Types.ConfiguredRpcResponse] {
    let out = Array.thaw<Types.ConfiguredRpcResponse>(state.runtime_rpcs);
    var i : Nat = 0;
    while (i < out.size()) {
      var j : Nat = i + 1;
      while (j < out.size()) {
        if (out[j].network < out[i].network) {
          let tmp = out[i];
          out[i] := out[j];
          out[j] := tmp;
        };
        j += 1;
      };
      i += 1;
    };
    Array.freeze(out)
  };

  public func configured_rpc(state : State, network : Text) : ?Text {
    for (r in state.runtime_rpcs.vals()) {
      if (r.network == network) {
        return ?r.rpc_url;
      };
    };
    null
  };

  public func upsert_configured_rpc(state : State, network0 : Text, rpc_url0 : Text) : (Bool, State) {
    let network = network0;
    let rpc_url = rpc_url0;
    let items = Buffer.Buffer<Types.ConfiguredRpcResponse>(state.runtime_rpcs.size() + 1);
    var found = false;
    var replaced = false;
    for (r in state.runtime_rpcs.vals()) {
      if (r.network == network) {
        found := true;
        replaced := (r.rpc_url != rpc_url);
        items.add({ network; rpc_url });
      } else {
        items.add(r);
      };
    };
    if (not found) {
      items.add({ network; rpc_url });
    };
    (
      replaced,
      {
        owner = state.owner;
        paused = state.paused;
        custom_tokens = state.custom_tokens;
        removed_tokens = state.removed_tokens;
        runtime_rpcs = Buffer.toArray(items);
      },
    )
  };

  public func remove_configured_rpc(state : State, network : Text) : (Bool, State) {
    let items = Buffer.Buffer<Types.ConfiguredRpcResponse>(state.runtime_rpcs.size());
    var removed = false;
    for (r in state.runtime_rpcs.vals()) {
      if (r.network == network) {
        removed := true;
      } else {
        items.add(r);
      };
    };
    (
      removed,
      {
        owner = state.owner;
        paused = state.paused;
        custom_tokens = state.custom_tokens;
        removed_tokens = state.removed_tokens;
        runtime_rpcs = Buffer.toArray(items);
      },
    )
  };

  func token_key_eq(aNetwork : Text, aToken : Text, bNetwork : Text, bToken : Text) : Bool {
    aNetwork == bNetwork and aToken == bToken
  };
}

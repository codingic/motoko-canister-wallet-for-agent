import Blob "mo:base/Blob";
import MoError "mo:base/Error";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import AppConfig "./config/app_config";
import WalletError "./error";

module {
  public type HttpHeader = {
    name : Text;
    value : Text;
  };

  public type HttpMethod = {
    #get;
    #head;
    #post;
    #put;
    #delete;
    #patch;
    #options;
  };

  public type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    method : HttpMethod;
    headers : [HttpHeader];
    body : ?Blob;
  };

  public type HttpRequestResult = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };

  let IC00 : actor {
    http_request : shared (HttpRequestArgs) -> async HttpRequestResult;
  } = actor "aaaaa-aa";

  public func http_request(
    args : HttpRequestArgs,
    op : Text,
  ) : async WalletError.WalletResult<HttpRequestResult> {
    try {
      let resp = await (with cycles = attached_http_cycles(args.max_response_bytes)) IC00.http_request(args);
      #Ok(resp)
    } catch e {
      #Err(#Internal(op # " http outcall failed: " # MoError.message(e)))
    }
  };

  public func json_request(
    url : Text,
    method : HttpMethod,
    body : ?Blob,
    max_response_bytes : Nat64,
    op : Text,
  ) : async WalletError.WalletResult<HttpRequestResult> {
    let hasBody = body != null;
    let baseHeaders : [HttpHeader] = [{ name = "accept"; value = "application/json" }];
    let headers = if (hasBody) {
      [
        { name = "accept"; value = "application/json" },
        { name = "content-type"; value = "application/json" },
      ];
    } else {
      baseHeaders;
    };

    let args : HttpRequestArgs = {
      url;
      max_response_bytes = ?max_response_bytes;
      method;
      headers;
      body;
    };
    await http_request(args, op)
  };

  public func get_json(
    url : Text,
    max_response_bytes : Nat64,
    op : Text,
  ) : async WalletError.WalletResult<HttpRequestResult> {
    await json_request(url, #get, null, max_response_bytes, op)
  };

  public func post_json(
    url : Text,
    body : Blob,
    max_response_bytes : Nat64,
    op : Text,
  ) : async WalletError.WalletResult<HttpRequestResult> {
    await json_request(url, #post, ?body, max_response_bytes, op)
  };

  public func post_text(
    url : Text,
    body : Blob,
    content_type : Text,
    accept : Text,
    max_response_bytes : Nat64,
    op : Text,
  ) : async WalletError.WalletResult<HttpRequestResult> {
    let args : HttpRequestArgs = {
      url;
      max_response_bytes = ?max_response_bytes;
      method = #post;
      headers = [
        { name = "content-type"; value = content_type },
        { name = "accept"; value = accept },
      ];
      body = ?body;
    };
    await http_request(args, op)
  };

  // Motoko does not auto-attach canister-http cycles like Rust's helper path may effectively do.
  // Scale attached cycles by response cap so small RPC calls do not fail with "out of cycles".
  func attached_http_cycles(max_response_bytes : ?Nat64) : Nat {
    let base = AppConfig.default_http_cycles();
    let responseCap = switch (max_response_bytes) {
      case (?n) Nat64.toNat(n);
      case null 64 * 1024;
    };
    // Conservative estimate; unused cycles are refunded. Tuned lower to reduce temporary
    // burst pressure when multiple UI requests run concurrently.
    let perByte : Nat = 10_000_000;
    base + (responseCap * perByte)
  };
}

import Blob "mo:base/Blob";
import MoError "mo:base/Error";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import AppConfig "./config/app_config";
import WalletError "./error";

module {
  public type TransformArgs = {
    response : HttpRequestResult;
    context : Blob;
  };

  public type TransformContext = {
    function : shared query TransformArgs -> async HttpRequestResult;
    context : Blob;
  };

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
    transform : ?TransformContext;
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
      let resp = await (with cycles = AppConfig.default_http_cycles()) IC00.http_request(args);
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
      transform = null;
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
      transform = null;
    };
    await http_request(args, op)
  };
}

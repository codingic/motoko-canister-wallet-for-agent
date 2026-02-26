import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import MoError "mo:base/Error";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Addressing "./addressing";
import AppConfig "./config/app_config";
import CfgTokenList "./config/token_list_config";
import RpcConfig "./config/rpc_config";
import Error "./error";
import JsonAst "./json/JSON";
import Outcall "./outcall";
import SolTx "./sdk/sol_tx";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.SOLANA;
  let SOL_DECIMALS : Nat8 = 9;
  let BASE64_ALPHABET : [Char] = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
    'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/',
  ];

  type SchnorrKeyId = {
    algorithm : Addressing.SchnorrAlgorithm;
    name : Text;
  };

  type SignWithSchnorrArgs = {
    message : Blob;
    derivation_path : [Blob];
    key_id : SchnorrKeyId;
    aux : ?Blob;
  };

  type SignWithSchnorrResult = {
    signature : Blob;
  };

  let Management : actor {
    sign_with_schnorr : shared (SignWithSchnorrArgs) -> async SignWithSchnorrResult;
  } = actor "aaaaa-aa";

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    await request_address_for_network(NETWORK_NAME)
  };

  public func request_address_for_network(network_name : Text) : async Error.WalletResult<Types.AddressResponse> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((public_key, key_name))) {
        if (public_key.size() != 32) {
          #Err(
            #Internal(
              "unexpected ed25519 public key length for sol address: " #
              Nat.toText(public_key.size())
            )
          )
        } else {
          #Ok({
            network = network_name;
            address = Addressing.base58_encode(public_key);
            public_key_hex = Addressing.hex_encode(public_key);
            key_name;
            message = ?"Derived from management canister Schnorr(ed25519) public key";
          })
        }
      };
    }
  };

  public func get_balance(req : Types.BalanceRequest) : async Error.WalletResult<Types.BalanceResponse> {
    await get_balance_for_network_with_rpc(NETWORK_NAME, null, req)
  };

  public func get_balance_for_network(
    network_name : Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    await get_balance_for_network_with_rpc(network_name, null, req)
  };

  public func get_balance_for_network_with_rpc(
    network_name : Text,
    rpcOverride : ?Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    let account = Text.trim(req.account, #char ' ');
    if (Text.size(account) == 0) {
      return #Err(#InvalidInput("account is required"));
    };
    let tokenOpt : ?Text = switch (req.token) {
      case (?token) {
        let t = Text.trim(token, #char ' ');
        if (Text.size(t) == 0) null else ?t;
      };
      case null null;
    };

    switch (tokenOpt) {
      case (?mintText) {
        let tokenSupply = switch (await solana_rpc_call(
          network_name,
          "getTokenSupply",
          "[\"" # json_escape(mintText) # "\",{\"commitment\":\"confirmed\"}]",
          rpcOverride,
        )) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        let decimals : Nat8 = switch (json_object_field(tokenSupply, "value")) {
          case (?valueObj) {
            switch (json_object_field(valueObj, "decimals")) {
              case (?#Number(n)) {
                if (n < 0 or n > 255) return #Err(#Internal("solana rpc token decimals out of range"));
                Nat8.fromNat(Int.abs(n))
              };
              case (?#String(s)) {
                switch (nat_from_decimal_text(s)) {
                  case (?v) {
                    if (v > 255) return #Err(#Internal("solana rpc token decimals out of range"));
                    Nat8.fromNat(v)
                  };
                  case null return #Err(#Internal("solana rpc getTokenSupply missing decimals"));
                }
              };
              case (_) return #Err(#Internal("solana rpc getTokenSupply missing decimals"));
            }
          };
          case null return #Err(#Internal("solana rpc getTokenSupply missing value"));
        };

        let tokenAccounts = switch (await solana_rpc_call(
          network_name,
          "getTokenAccountsByOwner",
          "[\"" # json_escape(account) # "\"," #
          "{\"mint\":\"" # json_escape(mintText) # "\"}," #
          "{\"encoding\":\"jsonParsed\",\"commitment\":\"confirmed\"}]",
          rpcOverride,
        )) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };

        let firstPubkey : ?Text = switch (json_object_field(tokenAccounts, "value")) {
          case (?#Array(items)) {
            if (items.size() == 0) {
              null
            } else {
              switch (items[0]) {
                case (#Object(_)) {
                  switch (json_object_field(items[0], "pubkey")) {
                    case (?#String(s)) ?s;
                    case (_) null;
                  }
                };
                case (_) null;
              }
            }
          };
          case (_) null;
        };

        switch (firstPubkey) {
          case null {
            return #Ok({
              network = network_name;
              account = req.account;
              token = req.token;
              amount = ?"0";
              decimals = ?decimals;
              block_ref = null;
              pending = false;
              message = ?"RPC getTokenAccountsByOwner (no token account => balance 0)";
            });
          };
          case (?tokenAccountB58) {
            let tokenBal = switch (await solana_rpc_call(
              network_name,
              "getTokenAccountBalance",
              "[\"" # json_escape(tokenAccountB58) # "\",{\"commitment\":\"confirmed\"}]",
              rpcOverride,
            )) {
              case (#Err(err)) return #Err(err);
              case (#Ok(v)) v;
            };

            let slotText : ?Text = switch (json_object_field(tokenBal, "context")) {
              case (?ctxObj) {
                switch (json_object_field(ctxObj, "slot")) {
                  case (?#Number(n)) { if (n < 0) null else ?Int.toText(n) };
                  case (?#String(s)) ?s;
                  case (_) null;
                }
              };
              case null null;
            };
            let amountRawText = switch (json_object_field(tokenBal, "value")) {
              case (?valueObj) {
                switch (json_object_field(valueObj, "amount")) {
                  case (?#String(s)) s;
                  case (_) return #Err(#Internal("solana rpc getTokenAccountBalance missing amount"));
                }
              };
              case null return #Err(#Internal("solana rpc getTokenAccountBalance missing value"));
            };
            let amountRaw = switch (nat_from_decimal_text(amountRawText)) {
              case (?v) v;
              case null return #Err(#Internal("solana rpc getTokenAccountBalance amount is not u64"));
            };

            return #Ok({
              network = network_name;
              account = req.account;
              token = req.token;
              amount = ?format_units(amountRaw, Nat8.toNat(decimals));
              decimals = ?decimals;
              block_ref = slotText;
              pending = false;
              message = ?("RPC getTokenAccountBalance (" # tokenAccountB58 # ")");
            });
          };
        };
      };
      case null {};
    };

    let rpcResult = switch (await solana_rpc_call(
      network_name,
      "getBalance",
      "[\"" # json_escape(account) # "\",{\"commitment\":\"confirmed\"}]",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let slotText : ?Text = switch (json_object_field(rpcResult, "context")) {
      case (?ctxObj) {
        switch (json_object_field(ctxObj, "slot")) {
          case (?#Number(n)) { if (n < 0) null else ?Int.toText(n) };
          case (?#String(s)) ?s;
          case (_) null;
        }
      };
      case null null;
    };
    let lamports : Nat = switch (json_object_field(rpcResult, "value")) {
      case (?#Number(n)) {
        if (n < 0) return #Err(#Internal("sol balance is negative"));
        Int.abs(n)
      };
      case (?#String(s)) {
        switch (nat_from_decimal_text(s)) {
          case (?v) v;
          case null return #Err(#Internal("sol balance parse failed"));
        }
      };
      case (_) return #Err(#Internal("solana rpc getBalance missing value"));
    };

    #Ok({
      network = network_name;
      account = req.account;
      token = null;
      amount = ?format_units(lamports, 9);
      decimals = ?9;
      block_ref = slotText;
      pending = false;
      message = ?"RPC getBalance (formatted SOL)";
    })
  };

  public func transfer_sol(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_sol_for_network_with_rpc(NETWORK_NAME, null, req)
  };

  public func transfer_spl(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_spl_for_network_with_rpc(NETWORK_NAME, null, req)
  };

  public func transfer_sol_for_network(
    network_name : Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_sol_for_network_with_rpc(network_name, null, req)
  };

  public func transfer_sol_for_network_with_rpc(
    network_name : Text,
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (validate_transfer(req)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    switch (req.token) {
      case (?token) {
        if (Text.size(Text.trim(token, #char ' ')) > 0) {
          return #Err(#InvalidInput("native SOL transfer does not accept token parameter"));
        };
      };
      case null {};
    };
    let amountLamports = switch (parse_decimal_lamports(req.amount)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountLamports == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };

    let publicKey = switch (await fetch_managed_solana_pubkey("sol transfer")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let fromAddress = Addressing.base58_encode(publicKey);
    switch (req.from) {
      case (?fromOverride) {
        let normalized = Text.trim(fromOverride, #char ' ');
        if (Text.size(normalized) > 0 and normalized != fromAddress) {
          return #Err(#InvalidInput("from does not match canister-managed Solana address"));
        };
      };
      case null {};
    };

    let toPubkey = switch (SolTx.decode_solana_pubkey(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let recentBlockhash = switch (await fetch_recent_blockhash(network_name, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let message = switch (SolTx.encode_system_transfer_message(publicKey, toPubkey, recentBlockhash, amountLamports)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signature = switch (await sign_solana_message(message)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (signature.size() != 64) {
      return #Err(#Internal("unexpected ed25519 signature length: " # Nat.toText(signature.size())));
    };
    let rawTx = SolTx.encode_signed_transaction(signature, message);
    let txSig = switch (await send_raw_transaction(network_name, rawTx, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok({
      network = network_name;
      accepted = true;
      tx_id = ?txSig;
      message = "broadcasted raw transaction via sendTransaction: " # txSig;
    })
  };

  public func transfer_spl_for_network(
    network_name : Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    await transfer_spl_for_network_with_rpc(network_name, null, req)
  };

  public func transfer_spl_for_network_with_rpc(
    network_name : Text,
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    switch (validate_transfer(req)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(())) {};
    };
    let mintText = switch (req.token) {
      case (?t) {
        let trimmed = Text.trim(t, #char ' ');
        if (Text.size(trimmed) == 0) {
          return #Err(#InvalidInput("token (SPL mint) is required"));
        };
        trimmed
      };
      case null return #Err(#InvalidInput("token (SPL mint) is required"));
    };
    let mint = switch (SolTx.decode_solana_pubkey(mintText)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let destinationOwner = switch (SolTx.decode_solana_pubkey(req.to)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let decimals = switch (await fetch_spl_decimals(network_name, mint, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let amountRaw = switch (parse_decimal_u64_units(req.amount, decimals)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (amountRaw == 0) {
      return #Err(#InvalidInput("amount must be > 0"));
    };

    let ownerPubkey = switch (await fetch_managed_solana_pubkey("spl transfer")) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let ownerAddress = Addressing.base58_encode(ownerPubkey);
    switch (req.from) {
      case (?fromOverride) {
        let normalized = Text.trim(fromOverride, #char ' ');
        if (Text.size(normalized) > 0 and normalized != ownerAddress) {
          return #Err(#InvalidInput("from does not match canister-managed Solana address"));
        };
      };
      case null {};
    };

    let sourceTokenAccount = switch (await fetch_token_account_for_owner(network_name, ownerPubkey, mint, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let destPlan = switch (await fetch_token_account_for_owner_optional(network_name, destinationOwner, mint, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(?v)) { { account = v; create_ata = false } };
      case (#Ok(null)) {
        let ata = switch (SolTx.derive_associated_token_address(destinationOwner, mint)) {
          case (#Err(err)) return #Err(err);
          case (#Ok(v)) v;
        };
        { account = ata; create_ata = true }
      };
    };
    let recentBlockhash = switch (await fetch_recent_blockhash(network_name, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let message = switch (
      encode_spl_transfer_checked_message(
        ownerPubkey,
        sourceTokenAccount,
        destPlan.account,
        destinationOwner,
        mint,
        recentBlockhash,
        amountRaw,
        decimals,
        destPlan.create_ata,
      )
    ) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let signature = switch (await sign_solana_message(message)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    if (signature.size() != 64) {
      return #Err(#Internal("unexpected ed25519 signature length: " # Nat.toText(signature.size())));
    };
    let rawTx = SolTx.encode_signed_transaction(signature, message);
    let txSig = switch (await send_raw_transaction(network_name, rawTx, rpcOverride)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    #Ok({
      network = network_name;
      accepted = true;
      tx_id = ?txSig;
      message = (if (destPlan.create_ata) {
        "broadcasted SPL transfer (with ATA create) via sendTransaction: "
      } else {
        "broadcasted SPL transfer via sendTransaction: "
      }) # txSig;
    })
  };

  public func discover_spl_token(
    network_name : Text,
    mint_text : Text,
  ) : async Error.WalletResult<Types.ConfiguredTokenResponse> {
    let mint = switch (SolTx.decode_solana_pubkey(mint_text)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let mintB58 = Addressing.base58_encode(mint);
    let decimals = switch (await fetch_spl_decimals(network_name, mint, null)) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };

    var symbol : ?Text = null;
    var name : ?Text = null;
    for (t in CfgTokenList.configured_tokens(network_name).vals()) {
      if (Text.trim(t.token_address, #char ' ') == mintB58) {
        symbol := ?t.symbol;
        name := ?t.name;
      };
    };
    let suffix = short_b58_suffix(mintB58);
    let finalSymbol = switch (symbol) {
      case (?s) {
        let t = Text.trim(s, #char ' ');
        if (Text.size(t) == 0) "SPL" # suffix else t
      };
      case null "SPL" # suffix;
    };
    let finalName = switch (name) {
      case (?n) {
        let t = Text.trim(n, #char ' ');
        if (Text.size(t) == 0) "SPL Token " # suffix else t
      };
      case null "SPL Token " # suffix;
    };

    #Ok({
      network = network_name;
      symbol = finalSymbol;
      name = finalName;
      token_address = mintB58;
      decimals = Nat8.toNat(decimals);
    })
  };

  func validate_transfer(req : Types.TransferRequest) : Error.WalletResult<()> {
    if (Text.size(Text.trim(req.to, #char ' ')) == 0) {
      return #Err(#InvalidInput("to is required"));
    };
    if (Text.size(Text.trim(req.amount, #char ' ')) == 0) {
      return #Err(#InvalidInput("amount is required"));
    };
    #Ok(())
  };

  func fetch_managed_solana_pubkey(op : Text) : async Error.WalletResult<[Nat8]> {
    let key = await Addressing.fetch_schnorr_public_key(#ed25519);
    switch (key) {
      case (#Err(err)) #Err(err);
      case (#Ok((public_key, _))) {
        if (public_key.size() != 32) {
          #Err(#Internal(
            "unexpected ed25519 public key length for " # op # ": " # Nat.toText(public_key.size())
          ))
        } else {
          #Ok(public_key)
        }
      };
    }
  };

  func fetch_recent_blockhash(network_name : Text, rpcOverride : ?Text) : async Error.WalletResult<[Nat8]> {
    let rpcResult = switch (await solana_rpc_call(
      network_name,
      "getLatestBlockhash",
      "[{\"commitment\":\"confirmed\"}]",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let blockhash = switch (json_object_field(rpcResult, "value")) {
      case (?valueObj) {
        switch (json_object_field(valueObj, "blockhash")) {
          case (?#String(s)) s;
          case (_) return #Err(#Internal("solana rpc getLatestBlockhash missing blockhash"));
        }
      };
      case null return #Err(#Internal("solana rpc getLatestBlockhash missing value"));
    };
    SolTx.decode_solana_pubkey(blockhash)
  };

  func sign_solana_message(message : [Nat8]) : async Error.WalletResult<[Nat8]> {
    let args : SignWithSchnorrArgs = {
      message = Blob.fromArray(message);
      derivation_path = [];
      key_id = {
        algorithm = #ed25519;
        name = AppConfig.default_schnorr_key_name();
      };
      aux = null;
    };
    try {
      let res = await Management.sign_with_schnorr(args);
      #Ok(Blob.toArray(res.signature))
    } catch e {
      #Err(#Internal("sign_with_schnorr failed: " # MoError.message(e)))
    }
  };

  func send_raw_transaction(network_name : Text, rawTx : [Nat8], rpcOverride : ?Text) : async Error.WalletResult<Text> {
    let rawBase64 = base64_encode(rawTx);
    let txSigValue = switch (await solana_rpc_call(
      network_name,
      "sendTransaction",
      "[\"" # rawBase64 # "\"," #
      "{\"encoding\":\"base64\",\"preflightCommitment\":\"confirmed\"}]",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (txSigValue) {
      case (#String(s)) #Ok(s);
      case (_) #Err(#Internal("solana rpc sendTransaction result is not string"));
    }
  };

  func fetch_spl_decimals(network_name : Text, mint : [Nat8], rpcOverride : ?Text) : async Error.WalletResult<Nat8> {
    let mintB58 = Addressing.base58_encode(mint);
    let rpcResult = switch (await solana_rpc_call(
      network_name,
      "getTokenSupply",
      "[\"" # mintB58 # "\",{\"commitment\":\"confirmed\"}]",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    switch (json_object_field(rpcResult, "value")) {
      case (?valueObj) {
        switch (json_object_field(valueObj, "decimals")) {
          case (?#Number(n)) {
            if (n < 0 or n > 255) #Err(#Internal("solana rpc token decimals out of range")) else #Ok(Nat8.fromNat(Int.abs(n)))
          };
          case (?#String(s)) {
            switch (nat_from_decimal_text(s)) {
              case (?v) {
                if (v > 255) #Err(#Internal("solana rpc token decimals out of range")) else #Ok(Nat8.fromNat(v))
              };
              case null #Err(#Internal("solana rpc getTokenSupply missing decimals"));
            }
          };
          case (_) #Err(#Internal("solana rpc getTokenSupply missing decimals"));
        }
      };
      case null #Err(#Internal("solana rpc getTokenSupply missing value"));
    }
  };

  func fetch_token_account_for_owner(
    network_name : Text,
    owner : [Nat8],
    mint : [Nat8],
    rpcOverride : ?Text,
  ) : async Error.WalletResult<[Nat8]> {
    switch (await fetch_token_account_for_owner_optional(network_name, owner, mint, rpcOverride)) {
      case (#Err(err)) #Err(err);
      case (#Ok(?account)) #Ok(account);
      case (#Ok(null)) #Err(#InvalidInput("destination/source token account not found for this mint"));
    }
  };

  func fetch_token_account_for_owner_optional(
    network_name : Text,
    owner : [Nat8],
    mint : [Nat8],
    rpcOverride : ?Text,
  ) : async Error.WalletResult<?[Nat8]> {
    let ownerB58 = Addressing.base58_encode(owner);
    let mintB58 = Addressing.base58_encode(mint);
    let rpcResult = switch (await solana_rpc_call(
      network_name,
      "getTokenAccountsByOwner",
      "[\"" # ownerB58 # "\"," #
      "{\"mint\":\"" # mintB58 # "\"}," #
      "{\"encoding\":\"jsonParsed\",\"commitment\":\"confirmed\"}]",
      rpcOverride,
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    let firstPubkey : ?Text = switch (json_object_field(rpcResult, "value")) {
      case (?#Array(items)) {
        if (items.size() == 0) {
          null
        } else {
          switch (items[0]) {
            case (#Object(_)) {
              switch (json_object_field(items[0], "pubkey")) {
                case (?#String(s)) ?s;
                case (_) null;
              }
            };
            case (_) null;
          }
        }
      };
      case (_) null;
    };
    switch (firstPubkey) {
      case (?s) {
        switch (SolTx.decode_solana_pubkey(s)) {
          case (#Err(err)) #Err(err);
          case (#Ok(v)) #Ok(?v);
        }
      };
      case null #Ok(null);
    }
  };

  func encode_spl_transfer_checked_message(
    ownerPubkey : [Nat8],
    sourceTokenAccount : [Nat8],
    destTokenAccount : [Nat8],
    destinationOwner : [Nat8],
    mint : [Nat8],
    recentBlockhash : [Nat8],
    amountRaw : Nat,
    decimals : Nat8,
    createDestinationAta : Bool,
  ) : Error.WalletResult<[Nat8]> {
    SolTx.encode_spl_transfer_checked_message(
      ownerPubkey,
      sourceTokenAccount,
      destTokenAccount,
      destinationOwner,
      mint,
      recentBlockhash,
      amountRaw,
      decimals,
      createDestinationAta,
    )
  };

  func short_b58_suffix(t : Text) : Text {
    let chars = Buffer.Buffer<Char>(Text.size(t));
    for (c in t.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    let keep : Nat = 6;
    if (arr.size() <= keep) return t;
    var out = "";
    var i = arr.size() - keep;
    while (i < arr.size()) {
      out #= Text.fromChar(arr[i]);
      i += 1;
    };
    out
  };

  func parse_decimal_lamports(value : Text) : Error.WalletResult<Nat> {
    switch (parse_decimal_u64_units(value, SOL_DECIMALS)) {
      case (#Err(err)) #Err(err);
      case (#Ok(v)) #Ok(v);
    }
  };

  func parse_decimal_u64_units(value : Text, decimals : Nat8) : Error.WalletResult<Nat> {
    let units = switch (parse_decimal_units(value, Nat8.toNat(decimals))) {
      case (#Err(err)) return #Err(err);
      case (#Ok(v)) v;
    };
    nat_to_u64(units)
  };

  func parse_decimal_units(value : Text, decimals : Nat) : Error.WalletResult<Nat> {
    let v = Text.trim(value, #char ' ');
    if (Text.size(v) == 0) return #Err(#InvalidInput("amount is required"));
    if (Text.startsWith(v, #char '-')) return #Err(#InvalidInput("amount must be positive"));
    let parts = Buffer.Buffer<Text>(3);
    var current = "";
    for (c in v.chars()) {
      if (c == '.') {
        parts.add(current);
        current := "";
      } else {
        current #= Text.fromChar(c);
      };
    };
    parts.add(current);
    let arr = Buffer.toArray(parts);
    if (arr.size() > 2) return #Err(#InvalidInput("amount format is invalid"));
    let whole = arr[0];
    let fracOpt : ?Text = if (arr.size() == 2) ?arr[1] else null;
    if (Text.size(whole) > 0) {
      for (c in whole.chars()) {
        if (c < '0' or c > '9') return #Err(#InvalidInput("amount must be decimal"));
      };
    };
    var wholeNum : Nat = 0;
    if (Text.size(whole) > 0) {
      switch (nat_from_decimal_text(whole)) {
        case (?v0) wholeNum := v0;
        case null return #Err(#InvalidInput("amount is too large"));
      };
    };
    let scale = pow10(decimals);
    var units = switch (nat_mul_checked(wholeNum, scale)) {
      case (?n) n;
      case null return #Err(#InvalidInput("amount is too large"));
    };
    switch (fracOpt) {
      case (?fracPart) {
        for (c in fracPart.chars()) {
          if (c < '0' or c > '9') return #Err(#InvalidInput("amount must be decimal"));
        };
        if (Text.size(fracPart) > decimals) return #Err(#InvalidInput("too many decimal places"));
        var fracText = fracPart;
        while (Text.size(fracText) < decimals) {
          fracText #= "0";
        };
        if (Text.size(fracText) > 0) {
          let fracNum = switch (nat_from_decimal_text(fracText)) {
            case (?n) n;
            case null return #Err(#InvalidInput("amount is too large"));
          };
          units := switch (nat_add_checked(units, fracNum)) {
            case (?n) n;
            case null return #Err(#InvalidInput("amount is too large"));
          };
        };
      };
      case null {};
    };
    #Ok(units)
  };

  func nat_to_u64(n : Nat) : Error.WalletResult<Nat> {
    if (n > 18_446_744_073_709_551_615) {
      #Err(#InvalidInput("amount is too large"))
    } else {
      #Ok(n)
    }
  };

  func nat_add_checked(a : Nat, b : Nat) : ?Nat {
    let c = a + b;
    if (c < a or c < b) null else ?c
  };

  func nat_mul_checked(a : Nat, b : Nat) : ?Nat {
    if (a == 0 or b == 0) return ?0;
    let c = a * b;
    if ((c / a) != b) null else ?c
  };

  func base64_encode(data : [Nat8]) : Text {
    if (data.size() == 0) return "";
    var out = "";
    var i : Nat = 0;
    while (i + 3 <= data.size()) {
      let n : Nat32 =
        (Nat32.fromNat(Nat8.toNat(data[i])) << 16) |
        (Nat32.fromNat(Nat8.toNat(data[i + 1])) << 8) |
        Nat32.fromNat(Nat8.toNat(data[i + 2]));
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 18) & 0x3f)]);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 12) & 0x3f)]);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 6) & 0x3f)]);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat(n & 0x3f)]);
      i += 3;
    };
    let rem = data.size() - i;
    if (rem == 1) {
      let n : Nat32 = Nat32.fromNat(Nat8.toNat(data[i])) << 16;
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 18) & 0x3f)]);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 12) & 0x3f)]);
      out #= "==";
    } else if (rem == 2) {
      let n : Nat32 =
        (Nat32.fromNat(Nat8.toNat(data[i])) << 16) |
        (Nat32.fromNat(Nat8.toNat(data[i + 1])) << 8);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 18) & 0x3f)]);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 12) & 0x3f)]);
      out #= Text.fromChar(BASE64_ALPHABET[Nat32.toNat((n >> 6) & 0x3f)]);
      out #= "=";
    };
    out
  };

  func json_object_field(value : JsonAst.JSON, key : Text) : ?JsonAst.JSON {
    switch (value) {
      case (#Object(fields)) {
        for ((k, v) in fields.vals()) {
          if (k == key) return ?v;
        };
        null
      };
      case (_) null;
    }
  };

  func _json_bool_field(value : JsonAst.JSON, key : Text) : ?Bool {
    switch (json_object_field(value, key)) {
      case (?#Boolean(b)) ?b;
      case (_) null;
    }
  };

  func solana_rpc_call(
    network_name : Text,
    method : Text,
    paramsJson : Text,
    rpcOverride : ?Text,
  ) : async Error.WalletResult<JsonAst.JSON> {
    let rpcUrl = switch (RpcConfig.resolve_rpc_url(network_name, rpcOverride)) {
      case (#ok(url)) url;
      case (#err(msg)) return #Err(#Internal("rpc url resolution failed: " # msg));
    };
    let bodyText =
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"" # json_escape(method) # "\",\"params\":" # paramsJson # "}";
    let httpRes = switch (await Outcall.post_json(
      rpcUrl,
      Text.encodeUtf8(bodyText),
      solana_rpc_max_response_bytes_for_method(method),
      "solana rpc",
    )) {
      case (#Err(err)) return #Err(err);
      case (#Ok(resp)) resp;
    };
    if (httpRes.status != 200) {
      let bodyTextResp = switch (Text.decodeUtf8(httpRes.body)) {
        case (?t) t;
        case null "<non-utf8>";
      };
      return #Err(#Internal("solana rpc http status " # Nat.toText(httpRes.status) # ": " # truncate_text(bodyTextResp, 240)));
    };
    let payloadText = switch (Text.decodeUtf8(httpRes.body)) {
      case (?t) t;
      case null return #Err(#Internal("parse solana rpc response failed: non-utf8"));
    };
    let payload = switch (JsonAst.parse(payloadText)) {
      case (?v) v;
      case null return #Err(#Internal("parse solana rpc response failed"));
    };
    switch (json_object_field(payload, "error")) {
      case (?errObj) {
        let codeText = switch (json_object_field(errObj, "code")) {
          case (?#Number(n)) Int.toText(n);
          case (?#String(s)) s;
          case (_) "?";
        };
        let msgText = switch (json_object_field(errObj, "message")) {
          case (?#String(s)) s;
          case (_) JsonAst.show(errObj);
        };
        return #Err(#Internal("solana rpc error " # codeText # ": " # msgText));
      };
      case null {};
    };
    switch (json_object_field(payload, "result")) {
      case (?v) #Ok(v);
      case null #Err(#Internal("solana rpc response missing result"));
    }
  };

  func solana_rpc_max_response_bytes_for_method(method : Text) : Nat64 {
    switch (method) {
      case ("getBalance") 4 * 1024 : Nat64;
      case ("getLatestBlockhash") 8 * 1024 : Nat64;
      case ("getTokenSupply") 8 * 1024 : Nat64;
      case ("getTokenAccountBalance") 8 * 1024 : Nat64;
      case ("getTokenAccountsByOwner") 48 * 1024 : Nat64;
      case ("sendTransaction") 8 * 1024 : Nat64;
      case (_) 16 * 1024 : Nat64;
    }
  };

  func nat_from_decimal_text(input : Text) : ?Nat {
    let t = Text.trim(input, #char ' ');
    if (Text.size(t) == 0) return null;
    var acc : Nat = 0;
    for (c in t.chars()) {
      if (c < '0' or c > '9') return null;
      acc := (acc * 10) + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
    };
    ?acc
  };

  func format_units(amount : Nat, decimals : Nat) : Text {
    if (decimals == 0) return Nat.toText(amount);
    let base = pow10(decimals);
    let whole = amount / base;
    let frac = amount % base;
    if (frac == 0) return Nat.toText(whole);
    let fracRaw = Nat.toText(frac);
    let zerosNeeded = if (Text.size(fracRaw) >= decimals) 0 else decimals - Text.size(fracRaw);
    let fracPadded = repeat_text("0", zerosNeeded) # fracRaw;
    Nat.toText(whole) # "." # trim_trailing_zeros(fracPadded)
  };

  func pow10(n : Nat) : Nat {
    var out : Nat = 1;
    var i : Nat = 0;
    while (i < n) { out *= 10; i += 1 };
    out
  };

  func repeat_text(piece : Text, n : Nat) : Text {
    var out = "";
    var i : Nat = 0;
    while (i < n) { out #= piece; i += 1 };
    out
  };

  func trim_trailing_zeros(s : Text) : Text {
    let chars = Buffer.Buffer<Char>(Text.size(s));
    for (c in s.chars()) { chars.add(c) };
    let arr = Buffer.toArray(chars);
    var end = arr.size();
    while (end > 0 and arr[end - 1] == '0') { end -= 1 };
    if (end == 0) return "0";
    var out = "";
    var i : Nat = 0;
    while (i < end) { out #= Text.fromChar(arr[i]); i += 1 };
    out
  };

  func json_escape(value : Text) : Text {
    var out = "";
    for (c in value.chars()) {
      if (c == '\\') {
        out #= "\\\\";
      } else if (c == '\"') {
        out #= "\\\"";
      } else if (c == '\n') {
        out #= "\\n";
      } else if (c == '\r') {
        out #= "\\r";
      } else if (c == '\t') {
        out #= "\\t";
      } else {
        out #= Text.fromChar(c);
      };
    };
    out
  };

  func truncate_text(t : Text, maxChars : Nat) : Text {
    if (Text.size(t) <= maxChars) return t;
    var out = "";
    var i : Nat = 0;
    for (c in t.chars()) {
      if (i >= maxChars) return out;
      out #= Text.fromChar(c);
      i += 1;
    };
    out
  };
}

import Error "./error";
import Sol "./solana";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.SOLANA_TESTNET;

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    await Sol.request_address_for_network(NETWORK_NAME)
  };

  public func get_balance(req : Types.BalanceRequest) : async Error.WalletResult<Types.BalanceResponse> {
    await Sol.get_balance_for_network(NETWORK_NAME, req)
  };

  public func get_balance_with_rpc(
    rpcOverride : ?Text,
    req : Types.BalanceRequest,
  ) : async Error.WalletResult<Types.BalanceResponse> {
    await Sol.get_balance_for_network_with_rpc(NETWORK_NAME, rpcOverride, req)
  };

  public func transfer_sol(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await Sol.transfer_sol_for_network(NETWORK_NAME, req)
  };

  public func transfer_sol_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    await Sol.transfer_sol_for_network_with_rpc(NETWORK_NAME, rpcOverride, req)
  };

  public func transfer_spl(req : Types.TransferRequest) : async Error.WalletResult<Types.TransferResponse> {
    await Sol.transfer_spl_for_network(NETWORK_NAME, req)
  };

  public func transfer_spl_with_rpc(
    rpcOverride : ?Text,
    req : Types.TransferRequest,
  ) : async Error.WalletResult<Types.TransferResponse> {
    await Sol.transfer_spl_for_network_with_rpc(NETWORK_NAME, rpcOverride, req)
  };
}

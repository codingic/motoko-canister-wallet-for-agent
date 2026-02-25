import Addressing "./addressing";
import Error "./error";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.ETHEREUM;

  public func request_address_for_network(network : Text) : async Error.WalletResult<Types.AddressResponse> {
    await Addressing.derive_evm_address(network)
  };

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    await request_address_for_network(NETWORK_NAME)
  };
}

import Addressing "./addressing";
import Error "./error";
import Types "./types";

module {
  let NETWORK_NAME : Text = Types.SEPOLIA;

  public func request_address() : async Error.WalletResult<Types.AddressResponse> {
    await Addressing.derive_evm_address(NETWORK_NAME)
  };
}

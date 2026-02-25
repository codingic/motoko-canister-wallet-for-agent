module {
  public type WalletError = {
    #Forbidden;
    #Paused;
    #InvalidInput : Text;
    #Unimplemented : {
      network : Text;
      operation : Text;
    };
    #Internal : Text;
  };

  public type WalletResult<T> = {
    #Ok : T;
    #Err : WalletError;
  };

  public func invalid_input(msg : Text) : WalletError {
    #InvalidInput(msg);
  };
}

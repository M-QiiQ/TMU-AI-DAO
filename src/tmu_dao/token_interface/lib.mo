import Nat "mo:base/Nat";
import Principal "mo:base/Principal";

module {
  public type Balance = Nat;
  public type Account = Principal;

  // واجهة Token فقط (Actor type)
  public type Token = actor {
    name        : query () -> async Text;
    symbol      : query () -> async Text;
    totalSupply : query () -> async Balance;
    balanceOf   : query (Account) -> async Balance;
    transfer    : (Account, Balance) -> async Bool;
    mint        : (Account, Balance) -> async ();
    burn        : (Balance) -> async Bool;
  };
}





import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Error "mo:base/Error";

actor Token {

  type Balance = Nat;
  type Account = Principal;

  stable var totalSupplyVar : Balance = 0;
  stable var balancesStore : [(Account, Balance)] = [];

  let balances = HashMap.HashMap<Account, Balance>(10, Principal.equal, Principal.hash);

  // 👇 هذا هو صاحب العقد، غيّره إذا لزم الأمر
  stable let owner : Principal = Principal.fromText("vadmv-dovmg-7wpws-i6moa-7tcxa-pywev-4wrbx-tjh7w-wfyxv-uwl2x-5ae");

  system func preupgrade() {
    balancesStore := Iter.toArray(balances.entries());
  };

  system func postupgrade() {
    for ((acc, bal) in balancesStore.vals()) {
      balances.put(acc, bal);
    };
  };

  public query func name() : async Text {
    "TMU Token"
  };

  public query func symbol() : async Text {
    "TMU"
  };

  public query func totalSupply() : async Balance {
    totalSupplyVar
  };

  public query func balanceOf(account : Account) : async Balance {
    switch (balances.get(account)) {
      case null { 0 };
      case (?value) { value };
    }
  };

  // ✅ حماية: فقط المالك يستطيع تنفيذ mint
  public shared(msg) func mint(to : Account, amount : Balance) : async () {
    if (msg.caller != owner) {
      Debug.print("Unauthorized mint attempt by " # Principal.toText(msg.caller));
      throw Error.reject("Only the owner can mint tokens.");
    };

    let current = switch (balances.get(to)) {
      case null { 0 };
      case (?value) { value };
    };
    balances.put(to, current + amount);
    totalSupplyVar += amount;
  };

  public shared(msg) func transfer(to : Account, amount : Balance) : async Bool {
    let from = msg.caller;

    let senderBalance = switch (balances.get(from)) {
      case null { 0 };
      case (?value) { value };
    };

    if (senderBalance < amount) {
      return false;
    };

    balances.put(from, senderBalance - amount);

    let receiverBalance = switch (balances.get(to)) {
      case null { 0 };
      case (?value) { value };
    };
    balances.put(to, receiverBalance + amount);

    return true;
  };

  // ✅ دالة burn: يقوم صاحب الحساب بحرق التوكن من رصيده
  public shared(msg) func burn(amount : Balance) : async Bool {
    let caller = msg.caller;

    let currentBalance = switch (balances.get(caller)) {
      case null { 0 };
      case (?value) { value };
    };

    if (currentBalance < amount) {
      return false;
    };

    balances.put(caller, currentBalance - amount);
    totalSupplyVar -= amount;

    return true;
  };
};






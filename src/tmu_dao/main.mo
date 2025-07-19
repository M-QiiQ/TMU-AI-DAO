import Debug "mo:base/Debug";

actor TMUDAO {
    public func greet(name : Text) : async Text {
        Debug.print("TMU DAO greets " # name);
        return "Hello, " # name # "! Welcome to TMU DAO.";
    }
}

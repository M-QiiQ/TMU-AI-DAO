// src/tmu_dao/main.mo

import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Error "mo:base/Error";

actor TMUDAO {

  // =========================
  //        TOKEN LOGIC
  // =========================

  public type Balance = Nat;
  public type Account = Principal;

  stable var totalSupplyVar : Balance = 0;
  stable var balancesStore : [(Account, Balance)] = [];
  stable var owner : ?Principal = null;

  var balances = HashMap.HashMap<Account, Balance>(10, Principal.equal, Principal.hash);

  public query func name() : async Text { "TMU Token" };
  public query func symbol() : async Text { "TMU" };
  public query func totalSupply() : async Balance { totalSupplyVar };

  public query func balanceOf(account : Account) : async Balance {
    switch (balances.get(account)) { case null { 0 }; case (?v) { v } }
  };

  public query func getOwner() : async ?Principal { owner };

  // تعيين المالك لأول مرة فقط أو تغييره لاحقاً من طرف المالك الحالي
  public shared(msg) func setOwner(newOwner : Principal) : async Text {
    switch (owner) {
      case null {
        owner := ?newOwner;
        "✅ Owner initialized."
      };
      case (?o) {
        if (msg.caller != o) { return "⛔ Only owner can set a new owner." };
        owner := ?newOwner;
        "✅ Owner updated."
      };
    }
  };

  // mint: فقط المالك
  public shared(msg) func mint(to : Account, amount : Balance) : async Text {
    switch (owner) {
      case null { return "⛔ Owner not set. Call setOwner first."; };
      case (?o) {
        if (msg.caller != o) { return "⛔ Only the owner can mint tokens."; };
      };
    };

    let current = switch (balances.get(to)) { case null { 0 }; case (?v) { v } };
    balances.put(to, current + amount);
    totalSupplyVar += amount;
    "✅ Minted " # Nat.toText(amount) # " TMU to " # Principal.toText(to)
  };

  // transfer: caller → to
  public shared(msg) func transfer(to : Account, amount : Balance) : async Text {
    let from = msg.caller;
    let senderBalance = switch (balances.get(from)) { case null { 0 }; case (?v) { v } };
    if (senderBalance < amount) { return "⛔ Insufficient balance"; };

    balances.put(from, senderBalance - amount);

    let receiverBalance = switch (balances.get(to)) { case null { 0 }; case (?v) { v } };
    balances.put(to, receiverBalance + amount);

    "✅ Transferred " # Nat.toText(amount) # " TMU to " # Principal.toText(to)
  };

  // burn: caller يحرق من رصيده
  public shared(msg) func burn(amount : Balance) : async Text {
    let caller = msg.caller;
    let currentBalance = switch (balances.get(caller)) { case null { 0 }; case (?v) { v } };
    if (currentBalance < amount) { return "⛔ Insufficient balance to burn"; };

    balances.put(caller, currentBalance - amount);
    totalSupplyVar -= amount;
    "🔥 Burned " # Nat.toText(amount) # " TMU"
  };

  // =========================
  //     GOVERNANCE LOGIC
  // =========================

  public type ProposalId = Int;
  public type Vote = { #yes; #no };

  public type Proposal = {
    id: ProposalId;
    title: Text;
    description: Text;
    createdAt: Time.Time;
    votesYes: Nat;
    votesNo: Nat;
    deadline: Time.Time;
    passed: Bool;
    resolved: Bool;
  };

  stable var proposalsStore : [(ProposalId, Proposal)] = [];
  stable var nextProposalId : ProposalId = 0;

  var proposals = HashMap.HashMap<ProposalId, Proposal>(0, Int.equal, Int.hash);

  public shared(msg) func submitProposal(title: Text, description: Text, durationSeconds: Nat) : async ProposalId {
    let now = Time.now();
    let deadline = now + (durationSeconds * 1_000_000_000);

    let proposal : Proposal = {
      id = nextProposalId;
      title = title;
      description = description;
      createdAt = now;
      votesYes = 0;
      votesNo = 0;
      deadline = deadline;
      passed = false;
      resolved = false;
    };

    proposals.put(nextProposalId, proposal);
    nextProposalId += 1;
    proposal.id
  };

  public shared(msg) func vote(proposalId: ProposalId, v: Vote) : async Text {
    switch (proposals.get(proposalId)) {
      case null { "⛔ Proposal not found." };
      case (?p) {
        if (Time.now() > p.deadline) { return "⛔ Voting period has ended." };

        let updated = switch (v) {
          case (#yes) { { p with votesYes = p.votesYes + 1 } };
          case (#no)  { { p with votesNo = p.votesNo + 1 } };
        };

        proposals.put(proposalId, updated);
        "✅ Vote recorded."
      };
    }
  };

  public shared(msg) func resolveProposal(proposalId: ProposalId) : async Text {
    switch (proposals.get(proposalId)) {
      case null { "⛔ Proposal not found." };
      case (?p) {
        if (Time.now() < p.deadline) { return "⏳ Voting still in progress."; };
        if (p.resolved) { return "⚠️ Proposal already resolved."; };

        let passed = p.votesYes > p.votesNo;
        let updated = { p with passed = passed; resolved = true };
        proposals.put(proposalId, updated);
        if (passed) { "🎉 Proposal passed." } else { "❌ Proposal rejected." }
      };
    }
  };

  public query func getProposal(proposalId: ProposalId) : async ?Proposal {
    proposals.get(proposalId)
  };

  // =========================
  //  UPGRADE HOOKS
  // =========================

  system func preupgrade() {
    balancesStore := Iter.toArray(balances.entries());
    proposalsStore := Iter.toArray(proposals.entries());
  };

  system func postupgrade() {
    balances := HashMap.fromIter<Account, Balance>(balancesStore.vals(), 10, Principal.equal, Principal.hash);
    proposals := HashMap.fromIter<ProposalId, Proposal>(proposalsStore.vals(), 10, Int.equal, Int.hash);
  };
}






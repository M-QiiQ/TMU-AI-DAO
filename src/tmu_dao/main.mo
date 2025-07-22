import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";

actor TMUDAO {

  type ProposalId = Int;
  type Vote = { #yes; #no };

  type Proposal = {
    id: ProposalId;          // unique identifier for each proposal
    title: Text;             // short name of the proposal
    description: Text;       // detailed info
    createdAt: Time.Time;    // when it was submitted
    votesYes: Nat;           // number of Yes votes
    votesNo: Nat;            // number of No votes
    deadline: Time.Time;     // when voting closes
    passed: Bool;            // result (true = passed)
    resolved: Bool;          // whether the result has been finalized
  };

  var nextProposalId : ProposalId = 0;
  let proposals = HashMap.HashMap<ProposalId, Proposal>(0, Int.equal, Int.hash);

  public func submitProposal(title: Text, description: Text, durationSeconds: Nat) : async ProposalId {
    let now = Time.now();
    let deadline = now + (durationSeconds * 1_000_000_000); // convert seconds to nanoseconds

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
    return proposal.id;
  };

  public func vote(proposalId: ProposalId, vote: Vote) : async Text {
    switch (proposals.get(proposalId)) {
      case null { return "Proposal not found."; };
      case (?p) {
        if (Time.now() > p.deadline) {
          return "Voting period has ended.";
        };

        let updatedProposal = switch (vote) {
          case (#yes) { { p with votesYes = p.votesYes + 1 } };
          case (#no)  { { p with votesNo = p.votesNo + 1 } };
        };

        proposals.put(proposalId, updatedProposal);
        return "Vote recorded.";
      };
    }
  };


  public func resolveProposal(proposalId: ProposalId) : async Text {
    switch (proposals.get(proposalId)) {
      case null { return "Proposal not found."; };
      case (?p) {
        if (Time.now() < p.deadline) {
          return "Voting still in progress.";
        };
        if (p.resolved) {
          return "Proposal already resolved.";
        };

        let passed = p.votesYes > p.votesNo;
        let updated = { p with passed = passed; resolved = true };
        proposals.put(proposalId, updated);

        if (passed) {
          return "Proposal passed.";
        } else {
          return "Proposal rejected.";
        };
      };
    }
  };

  public query func getProposal(proposalId: ProposalId) : async ?Proposal {
    return proposals.get(proposalId);
  };
  
}

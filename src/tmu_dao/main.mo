import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";

actor TMUDAO {

  type ProposalId = Nat;
  type Vote = { #yes; #no };

  type Proposal = {
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

  var nextProposalId : ProposalId = 0;
  let proposals = HashMap.HashMap<ProposalId, Proposal>(0, Nat.equal, Nat.hash);

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

        if (vote == #yes) {
          p.votesYes += 1;
        } else {
          p.votesNo += 1;
        };

        proposals.put(proposalId, p);
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

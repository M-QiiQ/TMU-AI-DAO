// src/staking/StakingCanister.mo
import Nat       "mo:base/Nat";
import Nat64     "mo:base/Nat64";
import Principal "mo:base/Principal";
import Time      "mo:base/Time";
import HashMap   "mo:base/HashMap";
import Iter      "mo:base/Iter";
import Option    "mo:base/Option";
import Debug     "mo:base/Debug";

actor StakingCanister {

  // ---------------------- TYPES ----------------------
  public type Amount    = Nat;
  public type Timestamp = Nat64;

  public type StakeInfo = {
    staker         : Principal;
    amount         : Amount;
    startTimeNs    : Timestamp;   // IC time in ns
    lockPeriodSecs : Nat64;       // seconds
    claimedRewards : Amount;      // cumulative rewards already paid
  };

  // Your current Token interface
  type Token = actor {
    balanceOf : (owner : Principal) -> async Nat;
    transfer  : (to : Principal, amount : Nat) -> async Bool;
  };

  // ------------------- CONSTANTS/HELPERS -------------------
  let SECONDS_PER_YEAR : Nat64 = 31_536_000;
  let NANOS_PER_SEC    : Nat64 = 1_000_000_000;

  func nowNs() : Nat64 = Nat64.fromIntWrap(Time.now());

  func weightFor(lockSecs : Nat64) : Nat {
    if (lockSecs >= 3 * SECONDS_PER_YEAR) { 2 }
    else if (lockSecs >= 1 * SECONDS_PER_YEAR) { 1 }
    else { 1 };
  };

  // APR as fraction (_apr_num / _apr_den), e.g., 10/100 = 10%
  stable var _apr_num : Nat = 10;
  stable var _apr_den : Nat = 100;

  // ---------------------- STATE ----------------------
  stable var _stakes_kv           : [(Principal, StakeInfo)] = [];
  stable var _totalStaked         : Amount = 0;

  stable var _tokenPid            : ?Principal = null;  // Token canister principal
  stable var _governancePid       : ?Principal = null;  // Governance canister principal (TMUDAO)
  stable var _observedTreasuryBal : Amount = 0;         // staking canister's token balance (for PUSH verification)

  // Runtime map of stakes 
  var stakes = HashMap.HashMap<Principal, StakeInfo>(128, Principal.equal, Principal.hash);

  // ------------------- UPGRADE HOOKS -------------------
  system func preupgrade() {
    _stakes_kv := Iter.toArray(stakes.entries());
  };

  system func postupgrade() {
    // Rebuild map from stable snapshot
    stakes := HashMap.fromIter<Principal, StakeInfo>(
      _stakes_kv.vals(), 128, Principal.equal, Principal.hash
    );
  };

  // ------------------- INTERNAL UTILS -------------------
  func onlyGov(caller : Principal) {
    switch _governancePid {
      case (?g) {
        if (caller != g) { Debug.trap("⛔ Only governance can call this method") };
      };
      case null { Debug.trap("⛔ Governance not configured") };
    }
  };

  func token() : Token {
    switch _tokenPid {
      case (?p) { actor (Principal.toText(p)) : Token };
      case null { Debug.trap("⛔ Token canister not set") };
    }
  };

  // ------------------- ADMIN (GOV-ONLY) -------------------
  public shared(msg) func setTokenCanister(p : Principal) : async () {
    onlyGov(msg.caller);
    _tokenPid := ?p;

    // Initialize observed canister balance for PUSH flow
    let t = token();
    _observedTreasuryBal := await t.balanceOf(Principal.fromActor(StakingCanister));
  };

  public shared(msg) func setGovernanceCanister(p : Principal) : async () {
    // Allow first-time set by anyone (local), changes after that require gov
    if (_governancePid != null) { onlyGov(msg.caller) };
    _governancePid := ?p;
  };

  public shared(msg) func setAPR(num : Nat, den : Nat) : async () {
    onlyGov(msg.caller);
    if (den == 0) { Debug.trap("⛔ APR denominator must be > 0") };
    _apr_num := num; _apr_den := den;
  };

  // ------------------- STAKE (PUSH FLOW) -------------------
  // 1) User calls token.transfer(staking_canister, amount)
  // 2) User calls stakeAfterTransfer(amount, lockSecs)
  // Staking verifies its own token balance increased by >= amount.
  public shared(msg) func stakeAfterTransfer(amount : Amount, lockPeriodSecs : Nat64) : async Bool {
    if (amount == 0) { Debug.trap("⛔ Amount must be > 0") };

    let t = token();
    let before = _observedTreasuryBal;
    let nowBal = await t.balanceOf(Principal.fromActor(StakingCanister));
    if (nowBal < before + amount) {
      Debug.trap("⛔ Deposit not detected. Transfer tokens to the staking canister first.");
    };
    _observedTreasuryBal := nowBal;

    // Merge or create stake
    switch (stakes.get(msg.caller)) {
      case (?s) {
        let merged : StakeInfo = {
          staker         = s.staker;
          amount         = s.amount + amount;
          startTimeNs    = s.startTimeNs;  // preserve original start
          lockPeriodSecs = Nat64.max(s.lockPeriodSecs, lockPeriodSecs); // extend lock if longer
          claimedRewards = s.claimedRewards;
        };
        stakes.put(msg.caller, merged);
      };
      case null {
        let info : StakeInfo = {
          staker         = msg.caller;
          amount         = amount;
          startTimeNs    = nowNs();
          lockPeriodSecs = lockPeriodSecs;
          claimedRewards = 0;
        };
        stakes.put(msg.caller, info);
      };
    };

    _totalStaked += amount;
    true
  };

  // ------------------- UNSTAKE -------------------
  public shared(msg) func unstake() : async Amount {
    switch (stakes.get(msg.caller)) {
      case null { 0 };
      case (?s) {
        let elapsedSecs : Nat64 = (nowNs() - s.startTimeNs) / NANOS_PER_SEC;
        if (elapsedSecs < s.lockPeriodSecs) {
          Debug.trap("⛔ Stake is still locked");
        };

        let amt = s.amount;

        // 1) Pay principal first
        let t = token();
        let ok = await t.transfer(msg.caller, amt);
        if (not ok) {
          Debug.trap("⛔ Token transfer back to user failed");
        };

        // 2) Only now mutate state
        ignore stakes.remove(msg.caller);
        _totalStaked -= amt;

        // 3) Refresh cache
        _observedTreasuryBal := await t.balanceOf(Principal.fromActor(StakingCanister));

        amt
      };
    }
  };


  // ------------------- CLAIM REWARDS -------------------
  public shared(msg) func claimRewards() : async Amount {
    switch (stakes.get(msg.caller)) {
      case null { 0 };
      case (?s) {
        let elapsedSecs : Nat64 = (nowNs() - s.startTimeNs) / NANOS_PER_SEC;

        // reward = amount * (elapsedSecs / year) * (apr_num/apr_den)
        let base : Nat = s.amount * Nat64.toNat(elapsedSecs);
        let raw  : Nat = (base * _apr_num) / (Nat64.toNat(SECONDS_PER_YEAR) * _apr_den);
        let owing = if (raw > s.claimedRewards) { raw - s.claimedRewards } else { 0 };
        if (owing == 0) { return 0 };

        // pay rewards from staking canister's token balance
        let t = token();
        let ok = await t.transfer(msg.caller, owing);
        if (not ok) { Debug.trap("⛔ Reward transfer failed (insufficient staking balance?)") };

        // update observed balance and stake record
        _observedTreasuryBal := await t.balanceOf(Principal.fromActor(StakingCanister));
        let updated : StakeInfo = {
          staker         = s.staker;
          amount         = s.amount;
          startTimeNs    = s.startTimeNs;
          lockPeriodSecs = s.lockPeriodSecs;
          claimedRewards = s.claimedRewards + owing;
        };
        stakes.put(msg.caller, updated);
        owing
      };
    }
  };

  // ------------------- READ-ONLY -------------------
  public query func getStakeInfo(p : Principal) : async ?StakeInfo { stakes.get(p) };

  public query func getTotalStaked() : async Amount { _totalStaked };

  public query func getVotingPower(p : Principal) : async Nat {
    switch (stakes.get(p)) {
      case null { 0 };
      case (?s) { s.amount * weightFor(s.lockPeriodSecs) };
    }
  };

  public query func configAPR() : async (Nat, Nat) { (_apr_num, _apr_den) };

  public query func principals() : async (staking : Principal, token : ?Principal, governance : ?Principal) {
    (Principal.fromActor(StakingCanister), _tokenPid, _governancePid)
  };

  // Return cached staking-canister token balance (kept fresh by stake/claim/unstake/setTokenCanister)
  public query func stakingBalance() : async Amount {
    _observedTreasuryBal
  };

  // Optional: force-refresh the cache (update call; allowed to await)
  public shared(msg) func refreshStakingBalance() : async Amount {
    let t = token();
    _observedTreasuryBal := await t.balanceOf(Principal.fromActor(StakingCanister));
    _observedTreasuryBal
  };
}

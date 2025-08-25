import Nat       "mo:base/Nat";
import Nat64     "mo:base/Nat64";
import Principal "mo:base/Principal";
import Time      "mo:base/Time";
import HashMap   "mo:base/HashMap";
import Option    "mo:base/Option";
import Iter      "mo:base/Iter";
import Debug     "mo:base/Debug";

persistent actor StakingCanister {

  // ============================================================
  //                   CONFIG / FEATURE SWITCHES
  // ============================================================

  // [LOCAL-TEST-ONLY] Run with an internal fake balance ledger (no Token canister needed).
  // Set to false in production and wire a real Token canister.
  let DEV_MODE : Bool = true;

  // ============================================================
  //                          TYPES
  // ============================================================

  public type Amount    = Nat;
  public type Timestamp = Nat64;

  public type StakeInfo = {
    staker         : Principal;
    amount         : Amount;
    startTimeNs    : Timestamp;   // monotonic IC time, nanoseconds
    lockPeriodSecs : Nat64;       // lock duration in seconds
    claimedRewards : Amount;      // cumulative rewards paid
  };

  // Minimal DIP20-style token interface
  type Token = actor {
    allowance    : (owner : Principal, spender : Principal) -> async Nat;
    approve      : (spender : Principal, amount : Nat) -> async Bool;
    transfer     : (to : Principal, amount : Nat) -> async Bool;
    transferFrom : (from : Principal, to : Principal, amount : Nat) -> async Bool;
    balanceOf    : (owner : Principal) -> async Nat;
  };

  // ============================================================
  //                         CONSTANTS
  // ============================================================

  let SECONDS_PER_YEAR : Nat64 = 31_536_000;
  let NANOS_PER_SEC    : Nat64 = 1_000_000_000;

  func weightFor(lockSecs : Nat64) : Nat {
    // Governance bonus by duration
    if (lockSecs >= 3 * SECONDS_PER_YEAR) { 2 }
    else if (lockSecs >= 1 * SECONDS_PER_YEAR) { 1 }
    else { 1 };
  };

  // APR numerator/denominator (e.g., 10/100 = 10% APR)
  var _apr_num : Nat = 10;
  var _apr_den : Nat = 100;

  // ============================================================
  //                         STATE (STABLE)
  // ============================================================

  // stakes map 
  var _stakes_kv     : [(Principal, StakeInfo)] = [];
  var _totalStaked   : Amount = 0;

  // Optional accounting cap to limit total rewards payout
  var _rewardPoolCap : Amount = 0;

  // Wiring to external canisters for production
  var _tokenPid      : ?Principal = null;  // Token canister principal (PROD)
  var _governancePid : ?Principal = null;  // Governance canister principal (PROD)
  var _rewardsVault  : ?Principal = null;  // Optional external vault paying rewards (PROD)

  // ============================================================
  //                         RUNTIME MAPS
  // ============================================================

  flexible let stakes = HashMap.HashMap<Principal, StakeInfo>(64, Principal.equal, Principal.hash);

  // [LOCAL-TEST-ONLY] Fake balances so you can test without Token canister.
  var _devBalances_kv : [(Principal, Amount)] = [];
  flexible let devBalances = HashMap.HashMap<Principal, Amount>(64, Principal.equal, Principal.hash);

  // ============================================================
  //                         HELPERS
  // ============================================================

 
  func nowNs() : Nat64 = Nat64.fromIntWrap(Time.now());

  // Governance guard:
  // - [LOCAL-TEST-ONLY] the guard is bypassed so you can call admin setters.
  // - In PROD, only the governance principal may call admin methods.
  func onlyGov(caller : Principal) {
    if (DEV_MODE) { return }; // [LOCAL-TEST-ONLY] bypass admin guard
    switch _governancePid {
      case (?g) {
        if (caller != g) { Debug.trap("⛔ Only governance can call this method") };
      };
      case null { Debug.trap("⛔ Governance not configured") };
    }
  };

  // Token actor accessor
  func token() : Token {
    switch _tokenPid {
      case (?p) { actor (Principal.toText(p)) : Token };
      case null { Debug.trap("⛔ Token canister not set") };
    }
  };

  // [LOCAL-TEST-ONLY] Fake ledger helpers
  func dev_credit(p : Principal, amt : Amount) {
    let cur = Option.get(devBalances.get(p), 0);
    devBalances.put(p, cur + amt);
  };

  func dev_debit(p : Principal, amt : Amount) : Bool {
    let cur = Option.get(devBalances.get(p), 0);
    if (cur < amt) { return false };
    devBalances.put(p, cur - amt);
    true
  };

  // ============================================================
  //                       UPGRADE HOOKS
  // ============================================================

  system func preupgrade() {
    _stakes_kv := Iter.toArray(stakes.entries());
    // [LOCAL-TEST-ONLY]
    _devBalances_kv := Iter.toArray(devBalances.entries());
  };

  system func postupgrade() {
    for ((k, v) in _stakes_kv.vals()) { stakes.put(k, v) };
    // [LOCAL-TEST-ONLY]
    for ((k, v) in _devBalances_kv.vals()) { devBalances.put(k, v) };
  };

  // ============================================================
  //                        ADMIN (GOV)
  // ============================================================

  // In DEV_MODE these are callable by anyone (bypass guard). In PROD, restricted to governance.

  public shared(msg) func setTokenCanister(p : Principal) : async () {
    onlyGov(msg.caller); _tokenPid := ?p;
  };

  public shared(msg) func setGovernanceCanister(p : Principal) : async () {
    if (_governancePid != null) { onlyGov(msg.caller) }; // allow first-time set by controller/anyone in DEV
    _governancePid := ?p;
  };

  public shared(msg) func setAPR(num : Nat, den : Nat) : async () {
    onlyGov(msg.caller);
    if (den == 0) { Debug.trap("⛔ Denominator must be > 0") };
    _apr_num := num; _apr_den := den;
  };

  public shared(msg) func addRewardsCap(amount : Amount) : async () {
    onlyGov(msg.caller);
    _rewardPoolCap += amount;
  };

  public shared(msg) func setRewardsVault(p : Principal) : async () {
    onlyGov(msg.caller); _rewardsVault := ?p;
  };

  // ============================================================
  //                        STAKE
  // ============================================================

  public shared(msg) func stake(amount : Amount, lockPeriodSecs : Nat64) : async Bool {
    if (amount == 0) { Debug.trap("⛔ Stake amount must be > 0") };

    // Pull funds from user
    if (DEV_MODE) {
      if (not dev_debit(msg.caller, amount)) {
        Debug.trap("⛔ Insufficient dev balance"); // [LOCAL-TEST-ONLY]
      };
    } else {
      let t = token();
      
      let ok = await t.transferFrom(msg.caller, Principal.fromActor(StakingCanister), amount);
      if (not ok) { Debug.trap("⛔ transferFrom failed (approve missing or insufficient balance)") };
    };

    // Merge or create user stake
    switch (stakes.get(msg.caller)) {
      case (?s) {
        let merged : StakeInfo = {
          staker         = s.staker;
          amount         = s.amount + amount;
          startTimeNs    = s.startTimeNs; 
          lockPeriodSecs = Nat64.max(s.lockPeriodSecs, lockPeriodSecs);
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

  // ============================================================
  //                       UNSTAKE
  // ============================================================

  public shared(msg) func unstake() : async Amount {
    switch (stakes.get(msg.caller)) {
      case null { 0 };
      case (?s) {
        let elapsedSecs : Nat64 = (nowNs() - s.startTimeNs) / NANOS_PER_SEC;
        if (elapsedSecs < s.lockPeriodSecs) {
          Debug.trap("⛔ Stake is still locked");
        };
        let amt = s.amount;

        ignore stakes.remove(msg.caller);
        _totalStaked -= amt;

        if (DEV_MODE) {
          dev_credit(msg.caller, amt); // [LOCAL-TEST-ONLY]
        } else {
          let t = token();
          let ok = await t.transfer(msg.caller, amt);
          if (not ok) { Debug.trap("⛔ Transfer back to user failed") };
        };

        amt
      };
    }
  };

  // ============================================================
  //                        REWARDS: CLAIM
  // ============================================================

  public shared(msg) func claimRewards() : async Amount {
    switch (stakes.get(msg.caller)) {
      case null { 0 };
      case (?s) {
        let elapsedSecs : Nat64 = (nowNs() - s.startTimeNs) / NANOS_PER_SEC;

        // raw reward = amount * elapsedSecs/yr * APR
        //            = amount * elapsedSecs * apr_num / (yr * apr_den)
        let base : Nat = s.amount * Nat64.toNat(elapsedSecs);
        let raw  : Nat = (base * _apr_num) / (Nat64.toNat(SECONDS_PER_YEAR) * _apr_den);

        let owing = if (raw > s.claimedRewards) { raw - s.claimedRewards } else { 0 };
        if (owing == 0) { return 0 };

        // Respect accounting cap if set
        if (_rewardPoolCap > 0 and owing > _rewardPoolCap) {
          if (_rewardPoolCap == 0) { return 0 };
        };

        // Payout
        if (DEV_MODE) {
          dev_credit(msg.caller, owing); // [LOCAL-TEST-ONLY]
        } else {
          let t = token();
          let payer : Principal =
            switch _rewardsVault { case (?v) v; case null { Principal.fromActor(StakingCanister) } };

          var ok : Bool = false;
     
          if (payer == Principal.fromActor(StakingCanister)) {
            ok := await t.transfer(msg.caller, owing);
          } else {
            ok := await t.transferFrom(payer, msg.caller, owing);
          };
          if (not ok) { Debug.trap("⛔ Reward transfer failed") };
        };

        // Decrease accounting cap after paying
        if (_rewardPoolCap > 0) { _rewardPoolCap -= Nat.min(_rewardPoolCap, owing) };

        // Update stake record
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

  // ============================================================
  //                         READ-ONLY
  // ============================================================

  public query func getStakeInfo(p : Principal) : async ?StakeInfo { stakes.get(p) };

  public query func getTotalStaked() : async Amount { _totalStaked };

  public query func getVotingPower(p : Principal) : async Nat {
    switch (stakes.get(p)) { case null { 0 }; case (?s) { s.amount * weightFor(s.lockPeriodSecs) } }
  };

  public query func configAPR() : async (Nat, Nat) { (_apr_num, _apr_den) };

  public query func rewardPoolCap() : async Amount { _rewardPoolCap };

  // [LOCAL-TEST-ONLY] expose fake balance for testing UI/CLI
  public query func devBalanceOf(p : Principal) : async Amount {
    if (DEV_MODE) { Option.get(devBalances.get(p), 0) } else { 0 }
  };

  // [LOCAL-TEST-ONLY] credit fake tokens to caller for local tests
  public shared(msg) func devCredit(amount : Amount) : async () {
    if (DEV_MODE) { dev_credit(msg.caller, amount) }
  };
};

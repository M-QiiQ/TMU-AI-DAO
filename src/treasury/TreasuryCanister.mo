// src/treasury/TreasuryCanister.mo

import Nat       "mo:base/Nat";
import Nat64     "mo:base/Nat64";
import Principal "mo:base/Principal";
import Array     "mo:base/Array";
import Hash      "mo:base/Hash";
import HashMap   "mo:base/HashMap";
import Iter      "mo:base/Iter";
import Time      "mo:base/Time";
import Debug     "mo:base/Debug";


import TokenIf  "../tmu_dao/token_interface/lib";

actor TreasuryCanister {

  // -------- Types --------
  public type TxKind = { #Deposit; #Payout };
  public type Tx = {
    id      : Nat;
    kind    : TxKind;
    from    : Principal;
    to      : Principal;
    amount  : Nat;
    memo    : ?Text;
    ts      : Nat64;
    ref     : ?Nat;      // links to payout request id for #Payout
  };

  public type PayoutStatus = { #Pending; #Approved; #Executed; #Rejected };
  public type PayoutRequest = {
    id          : Nat;
    to          : Principal;
    amount      : Nat;
    memo        : ?Text;
    created_by  : Principal;
    approvals   : [Principal];
    status      : PayoutStatus;
    created_at  : Nat64;
    executed_at : ?Nat64;
  };

  // -------- Stable storage --------
  stable var _tokenCanister        : ?Principal = null;
  stable var _governanceCanister   : ?Principal = null; 
  stable var _signers              : [Principal] = [];
  stable var _threshold            : Nat = 2;

  stable var _txsStore             : [Tx] = [];
  stable var _payoutsStore         : [PayoutRequest] = [];
  stable var _nextTxId             : Nat = 0;
  stable var _nextPayoutId         : Nat = 0;


  stable var _lastLoggedBalance    : Nat = 0;

  // Runtime map (rebuilt on upgrade)
  let payoutsById = HashMap.HashMap<Nat, PayoutRequest>(128, Nat.equal, Hash.hash);


  // -------- Helpers --------
  func now64() : Nat64 = Nat64.fromIntWrap(Time.now());

  func isSigner(p: Principal) : Bool {
    Array.find<Principal>(_signers, func(x) { Principal.equal(x, p) }) != null
  };

  func ensureSigner(caller: Principal) {
    if (not isSigner(caller)) Debug.trap("Not authorized: caller is not a signer");
  };

  func ensureGovernance(caller: Principal) {
    switch (_governanceCanister) {
      case (?g) {
        if (not Principal.equal(caller, g)) Debug.trap("Governance only");
      };
      case null { Debug.trap("Governance not set"); };
    }
  };

  func tokenActor() : ?TokenIf.Token {
    switch (_tokenCanister) {
      case (?p) { ?(actor (Principal.toText(p)) : TokenIf.Token) };
      case null { null };
    }
  };

  func pushTx(tx: Tx) {
    _txsStore := Array.append(_txsStore, [tx]);
  };

  func replacePayout(updated: PayoutRequest) {
    payoutsById.put(updated.id, updated);
    _payoutsStore := Array.tabulate<PayoutRequest>(
      _payoutsStore.size(),
      func (i : Nat) : PayoutRequest {
        let old : PayoutRequest = _payoutsStore[i];
        if (old.id == updated.id) updated else old
      }
    );
  };


  // -------- Wiring --------
  /// Bootstrap: first call sets governance, later only governance can change it
  public shared ({ caller }) func setGovernance(p: Principal) : async () {
    switch (_governanceCanister) {
      case null { _governanceCanister := ?p };
      case (?g) {
        if (not Principal.equal(caller, g)) Debug.trap("Only current Governance can update governance");
        _governanceCanister := ?p;
      }
    }
  };

  public shared ({ caller }) func setToken(p: Principal) : async () {
    ensureGovernance(caller);
    _tokenCanister := ?p;
  };

  // -------- Admin (Governance-only) --------
  public shared ({ caller }) func addSigner(p: Principal) : async () {
    ensureGovernance(caller);
    if (not isSigner(p)) { _signers := Array.append(_signers, [p]) };
  };

  public shared ({ caller }) func removeSigner(p: Principal) : async () {
    ensureGovernance(caller);
    _signers := Array.filter<Principal>(
      _signers,
      func (x : Principal) : Bool { not Principal.equal(x, p) }
    );
    if (_threshold > _signers.size()) { _threshold := _signers.size() };
  };


  public shared ({ caller }) func setThreshold(n: Nat) : async () {
    ensureGovernance(caller);
    if (n == 0) Debug.trap("Threshold must be >= 1");
    if (n > _signers.size()) Debug.trap("Threshold cannot exceed signers count");
    _threshold := n;
  };

  // -------- Deposit logging & reconciliation --------
  /// Returns the token balance held by this Treasury (on-chain, source of truth)
  public shared func getOnchainBalance() : async ?Nat {
    switch (tokenActor()) {
      case null { null };
      case (?tok) {
        let bal = await tok.balanceOf(Principal.fromActor(TreasuryCanister));
        ?bal
      }
    }
  };

  /// Syncs _lastLoggedBalance with the actual on-chain balance (no tx log).
  /// Allowed to Governance or any signer.
  public shared ({ caller }) func reconcileBalance() : async ?Nat {
    let isGov = switch (_governanceCanister) { case (?g) { Principal.equal(caller, g) }; case null { false } };
    if (not isGov and not isSigner(caller)) Debug.trap("Only Governance or a signer may reconcile");

    switch (tokenActor()) {
      case null { null };
      case (?tok) {
        let bal = await tok.balanceOf(Principal.fromActor(TreasuryCanister));
        _lastLoggedBalance := bal;
        ?bal
      }
    }
  };

  /// Log a new deposit **iff** the on-chain balance increased since the last log.
  /// This is necessary because your Token doesn’t push callbacks.
  /// Restricted to Governance or any signer to avoid bogus “from” metadata.
  public shared ({ caller }) func notifyDeposit(from: Principal, memo: ?Text) : async Nat {
    let isGov = switch (_governanceCanister) { case (?g) { Principal.equal(caller, g) }; case null { false } };
    if (not isGov and not isSigner(caller)) Debug.trap("Only Governance or a signer can log deposits");
    switch (tokenActor()) {
      case null { Debug.trap("Token not set"); };
      case (?tok) {
        let selfP = Principal.fromActor(TreasuryCanister);
        let current = await tok.balanceOf(selfP);
        if (current <= _lastLoggedBalance) {
          Debug.trap("No new deposit detected on-chain");
        };
        let delta = current - _lastLoggedBalance;
        _lastLoggedBalance := current;

        let txId = _nextTxId; _nextTxId += 1;
        let tx : Tx = {
          id = txId; kind = #Deposit; from = from; to = selfP;
          amount = delta; memo = memo; ts = now64(); ref = null
        };
        pushTx(tx);
        txId
      }
    }
  };

  // -------- Payout lifecycle --------
  /// Governance creates payout intent
  public shared ({ caller }) func requestPayout(to: Principal, amount: Nat, memo: ?Text) : async Nat {
    ensureGovernance(caller);
    if (amount == 0) Debug.trap("Amount must be > 0");

    // Soft check against on-chain balance to catch obvious errors early
    switch (tokenActor()) {
      case null { Debug.trap("Token not set"); };
      case (?tok) {
        let bal = await tok.balanceOf(Principal.fromActor(TreasuryCanister));
        if (amount > bal) Debug.trap("Insufficient on-chain balance for this payout (consider reconciling or reducing amount)");
      }
    };

    let id = _nextPayoutId; _nextPayoutId += 1;
    let req : PayoutRequest = {
      id = id; to = to; amount = amount; memo = memo;
      created_by = caller; approvals = [];
      status = #Pending; created_at = now64(); executed_at = null
    };
    _payoutsStore := Array.append(_payoutsStore, [req]);
    payoutsById.put(id, req);
    id
  };

  /// Signer approvals (multisig)
  public shared ({ caller }) func approvePayout(id: Nat) : async Nat {
    ensureSigner(caller);
    switch (payoutsById.get(id)) {
      case null { Debug.trap("Payout not found") };
      case (?req) {
        if (req.status != #Pending and req.status != #Approved) Debug.trap("Payout not approvable");
        if (Array.find<Principal>(req.approvals, func(p) { Principal.equal(p, caller) }) != null) {
          return req.approvals.size();
        };
        let newApprovals = Array.append(req.approvals, [caller]);
        let newStatus : PayoutStatus = if (newApprovals.size() >= _threshold) { #Approved } else { #Pending };
        let updated : PayoutRequest = {
          id = req.id; to = req.to; amount = req.amount; memo = req.memo;
          created_by = req.created_by; approvals = newApprovals;
          status = newStatus; created_at = req.created_at; executed_at = req.executed_at
        };
        replacePayout(updated);
        newApprovals.size()
      }
    }
  };

  /// Execute on-chain transfer via Token (transfer is from Treasury to recipient)
  public shared ({ caller }) func executePayout(id: Nat) : async Bool {
    ensureSigner(caller);

    switch (payoutsById.get(id)) {
      case null { Debug.trap("Payout not found") };
      case (?req) {
        if (req.status != #Approved) Debug.trap("Payout is not approved");
        if (req.amount == 0) Debug.trap("Zero amount");
        switch (tokenActor()) {
          case null { Debug.trap("Token not set"); };
          case (?tok) {
            // Ensure we still have funds on-chain
            let selfP = Principal.fromActor(TreasuryCanister);
            let bal = await tok.balanceOf(selfP);
            if (req.amount > bal) Debug.trap("Insufficient on-chain balance at execution time");

            let ok = await tok.transfer(req.to, req.amount);
            if (not ok) Debug.trap("Token transfer failed");

            // Update logs and mark executed
            let txId = _nextTxId; _nextTxId += 1;
            let tx : Tx = {
              id = txId; kind = #Payout; from = selfP; to = req.to;
              amount = req.amount; memo = req.memo; ts = now64(); ref = ?req.id
            };
            pushTx(tx);

            let updated : PayoutRequest = {
              id = req.id; to = req.to; amount = req.amount; memo = req.memo;
              created_by = req.created_by; approvals = req.approvals;
              status = #Executed; created_at = req.created_at; executed_at = ?now64()
            };
            replacePayout(updated);

            // Optional: refresh last-logged balance so deposit logs remain consistent
            let newBal = await tok.balanceOf(selfP);
            _lastLoggedBalance := newBal;

            true
          }
        }
      }
    }
  };

  // -------- Reads --------
  public query func getTxs(from: Nat, limit: Nat) : async [Tx] {
    let n = _txsStore.size();
    if (from >= n) return [];
    let upto = Nat.min(n, from + limit);
    Array.subArray(_txsStore, from, upto - from)
  };

  public query func getPayout(id: Nat) : async ?PayoutRequest { payoutsById.get(id) };
  public query func getSigners() : async ([Principal], Nat) { (_signers, _threshold) };

  // -------- Upgrade hooks --------
  system func postupgrade() {
    for (req in Iter.fromArray(_payoutsStore)) { payoutsById.put(req.id, req) };
  };
  system func preupgrade() {};
}

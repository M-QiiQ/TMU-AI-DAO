import React, { useEffect, useState } from "react";
import { Actor, HttpAgent } from "@dfinity/agent";
import { idlFactory as governance_idl } from "./dfx/governance.did.js";
import { idlFactory as token_idl } from "./dfx/token.did.js";

// استبدل بالقيم ديال canister IDs عندك محلياً
const GOVERNANCE_CANISTER_ID = "bkyz2-fmaaa-aaaaa-qaaaq-cai"; // TMUDAO
const TOKEN_CANISTER_ID = "bd3sg-teaaa-aaaaa-qaaba-cai";      // Token

function App() {
  const [governance, setGovernance] = useState(null);
  const [token, setToken] = useState(null);

  const [proposals, setProposals] = useState([]);
  const [balance, setBalance] = useState(0);

  // حقول الفورم
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [duration, setDuration] = useState(60); // ثواني

  useEffect(() => {
    (async () => {
      const agent = new HttpAgent({ host: "http://127.0.0.1:4943" });
      try { await agent.fetchRootKey(); } 
      catch (e) { console.warn("fetchRootKey failed (ok on mainnet):", e); }

      const governanceActor = Actor.createActor(governance_idl, { agent, canisterId: GOVERNANCE_CANISTER_ID });
      const tokenActor = Actor.createActor(token_idl, { agent, canisterId: TOKEN_CANISTER_ID });

      setGovernance(governanceActor);
      setToken(tokenActor);

      // تحميل البيانات الأولية
      try {
        const list = await governanceActor.listProposals();
        setProposals(list);
      } catch (e) { console.error("Failed to load proposals:", e); }

      try {
        const principal = await agent.getPrincipal();
        const bal = await tokenActor.balanceOf(principal);
        setBalance(Number(bal.toString()));
      } catch (e) { console.error("Failed to load balance:", e); }
    })();
  }, []);

  const submitProposal = async (e) => {
    e.preventDefault();
    if (!governance) return;

    try {
      const id = await governance.submitProposal(
        title,
        description,
        window.BigInt(duration)
      );
      const list = await governance.listProposals();
      setProposals(list);
      setTitle("");
      setDescription("");
      setDuration(60);
    } catch (e) {
      console.error("submitProposal error:", e);
      alert("Failed to submit proposal. Check console.");
    }
  };

  // تحويل الوقت من ns إلى ms للعرض
  const fmtDeadline = (nsBigInt) => {
    try {
      const ms = Number(nsBigInt / window.BigInt(1_000_000));
      return new Date(ms).toLocaleString();
    } catch { return String(nsBigInt); }
  };

  return (
    <div style={{ maxWidth: 820, margin: "30px auto", fontFamily: "sans-serif" }}>
      <h1 style={{ marginBottom: 6 }}>TMU-AI-DAO</h1>
      <h2 style={{ marginTop: 0, color: "#666", fontWeight: 500 }}>Governance Dashboard</h2>

      <div style={{ padding: 16, border: "1px solid #eee", borderRadius: 12, marginBottom: 16, background: "#fafafa" }}>
        <strong>My Token Balance:</strong> {balance}
      </div>

      <div style={{ padding: 16, border: "1px solid #eee", borderRadius: 12, marginBottom: 24 }}>
        <h3 style={{ marginTop: 0 }}>Submit Proposal</h3>
        <form onSubmit={submitProposal}>
          <div style={{ marginBottom: 8 }}>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Title" required style={{ width: "100%", padding: 10 }} />
          </div>
          <div style={{ marginBottom: 8 }}>
            <input value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Description" required style={{ width: "100%", padding: 10 }} />
          </div>
          <div style={{ marginBottom: 8 }}>
            <label style={{ display: "block", marginBottom: 4 }}>Duration (seconds)</label>
            <input type="number" min="1" value={duration} onChange={(e) => setDuration(Number(e.target.value))} style={{ width: 140, padding: 8 }} />
          </div>
          <button type="submit" style={{ padding: "10px 16px" }}>Submit</button>
        </form>
      </div>

      <div style={{ padding: 16, border: "1px solid #eee", borderRadius: 12, marginBottom: 24 }}>
        <h3 style={{ marginTop: 0 }}>Proposals</h3>
        {proposals.length === 0 ? <p>No proposals yet.</p> :
          <ul>
            {proposals.map((p, idx) => (
              <li key={idx} style={{ marginBottom: 8, lineHeight: 1.5 }}>
                <strong>{p.title}</strong> — {p.description} | Yes: {p.votesYes} No: {p.votesNo} | Deadline: {fmtDeadline(p.deadline)}
              </li>
            ))}
          </ul>
        }
      </div>
    </div>
  );
}

export default App;



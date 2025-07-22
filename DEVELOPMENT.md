
# DEVELOPMENT.md

## 🛠️ Developer Guide: TMU AI DAO LLC on ICP

Welcome to the development guide for the **TMU AI DAO LLC RWA Tokenization** project. This document outlines how to set up, deploy, and interact with the decentralized governance system for our real-world LLC using the Internet Computer Protocol (ICP).

---

## 📦 Prerequisites

Before you begin, make sure the following tools are installed on your system:

- [DFX SDK](https://internetcomputer.org/docs/current/developer-docs/setup/install/) (v0.18.0 or higher)
- A Chromium-based browser (for wallet and II interaction)
- Plug Wallet or NFID for test voting or proposal submission

---

## 🧱 Project Structure

```bash
├── assets/
│   └── TMU_AI_DAO_PitchDeck.pdf    # Project PitchDeck
├── src/
│   └── main.mo                     # Motoko canister code
├── dfx.json                        # Canister configuration
├── sns_init.yaml                   # SNS launch parameters (optional)
├── README.md
└── DEVELOPMENT.md
```

---

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/tmu-ai-dao/tmu-rwa-sns.git
cd tmu-rwa-sns
```

---

### 2. Start the Local Internet Computer

Start the local replica in the background:

```bash
dfx start --background
```

If needed, you can reset with:

```bash
dfx stop
dfx start --clean --background
```

---

### 3. Deploy the Canister

```bash
dfx deploy
```

This deploys:

- The Motoko canister (`main.mo`)
- SNS-related configuration (if applicable)

---

## 🌐 Interacting with SNS (Testnet or Mainnet)

If deployed to mainnet/testnet, include the real SNS canister IDs:

```
Root Canister:      r7inp-6aaaa-aaaaa-aaabq-cai
Governance:         rdmx6-jaaaa-aaaaa-aaadq-cai
Ledger:             ryjl3-tyaaa-aaaaa-aaaba-cai
Swap:               rkp4c-7iaaa-aaaaa-aaaca-cai
Index (optional):   qhbym-qaaaa-aaaaa-aaafq-cai
```

You can interact via:

- [NNS dApp](https://nns.ic0.app) → "Add Custom SNS"
- CLI using `dfx canister call` commands

---

## 🧪 Local Test Workflow

If you have test functions inside `main.mo`, you can run them via:

```bash
dfx canister call <canister_name> <test_function>
```

---

## 🗳️ Voting and Proposals

Once deployed:

1. Connect your Plug/NFID wallet
2. Use the NNS frontend dApp or CLI to submit a proposal
3. Vote using governance tokens issued during SNS initialization
4. View state transitions and logs

---

## 📂 Legal and Compliance

TMU AI DAO LLC is a real-world registered entity.

While formal legal documentation (e.g., operating agreement, token mapping diagrams) is not included in this repository, the project is designed with real-world compliance in mind. Governance logic aims to reflect traditional ownership rights through token-based DAO structures on ICP.

---

## 🧠 Architecture Highlights

- **ICP SNS DAO Integration**: Designed to work with the Internet Computer’s SNS framework for decentralized governance.
- **Motoko Smart Contract**: Core logic written in Motoko to enable governance, tokenization, or DAO-related behavior.
- **Compliance-Aware Design**: Built with real-world application in mind, though formal legal alignment is still in progress.

---

## 🤝 Contributing

🚧 This project is currently under active development as part of a hackathon.  
While we welcome feedback and ideas, we are **not accepting external pull requests** at this time to comply with event rules.

After the hackathon, we may open up contributions. Stay tuned!

---

## 📄 License

This project is licensed under the **MIT License**. See `LICENSE` for more.

---

## 🔗 Resources

- [ICP SNS Docs](https://internetcomputer.org/docs/current/developer-docs/integrations/sns/)
- [NNS Frontend (SNS Launch Tool)](https://nns.ic0.app)
- [TMU.ai Website](https://tmu.ai)

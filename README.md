# TMU DAO

This project is a Motoko-based Service Nervous System (SNS) DAO on the Internet Computer.

## Project Summary

TMU DAO governs a real-world service infrastructure (video meetings, AI transcription, metadata storage). Inspired by:
- **EKOKE DAO** for its real-world asset tokenization framing
- **ICExplorer** for Web2 to Web3 governance transition

## Structure

- `dfx.json`: Declares the `tmu_dao` Motoko canister
- `sns_init.yaml`: SNS configuration
- `main.mo`: Motoko logic (simple greeting interface)

## How to Deploy

1. Replace `<YOUR_PRINCIPAL_ID>` in `sns_init.yaml` with your real Principal ID
2. Deploy canister:
   ```bash
   dfx deploy
   ```
3. Initialize SNS (once canister is ready):
   ```bash
   dfx sns deploy --config sns_init.yaml
   ```

---

This is a minimal SNS starter for TMU DAO development.

**New Features**

- **Guarantors**: a payer primitive that admits a transaction to the public mempool even when the sender's `VERIFY` frame is unsafe to simulate. Adopts [PR #11555](https://github.com/ethereum/EIPs/pull/11555) verbatim: `APPROVE_GUARANTEE = 0x4` scope, `compute_frame_sig_hash`, `guarantor_approved`, canonical paymaster guarantor mode with `bumpNonce`.
- **Keyed Nonces**: independent replay-protection sequences per `(sender, signer)`. Mirrors [EIP-8250](https://github.com/ethereum/EIPs/pull/11598) semantics. Diverges only in shape: one `uint64 signer` envelope field instead of `(nonce_key, nonce_seq)`, so the same identifier indexes the keyed nonce and the registered pubkey.
- **Signer Binding**: tx-scoped `verified_signers` table populated by non-secp256k1 `VERIFY` frames that prove `(digest, address)` against a registered pubkey. `ECRECOVER` consults the table on the hit path; miss path is byte-identical to upstream.

**Protocol Changes**

- One envelope field: `signer` (uint64).
- One system contract: `AUTH_MANAGER` at a reserved address (EIP-4788 / EIP-2935 pattern)
- Zero new opcodes, zero new precompiles, zero account-RLP changes.

**Related PRs**

- [Guarantors (#11555)](https://github.com/ethereum/EIPs/pull/11555) by Derek Chiang
- [Keyed Nonces (EIP-8250, #11598)](https://github.com/ethereum/EIPs/pull/11598) by Thomas Thiery et al.
- [EIP-8164 Key Delegation](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md) by Gregory Markou et al.

Authors of those proposals are credited in the EIP `author` header.

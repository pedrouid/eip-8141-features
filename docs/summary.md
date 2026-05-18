# Extend EIP-8141 with Guarantors, Keyed Nonces, and Signer Binding

Three additions over upstream EIP-8141, scoped to the minimum spec delta and aligned with active related PRs.

**Features**

- **Guarantors**: a payer primitive that admits a transaction to the public mempool even when the sender's `VERIFY` frame is unsafe to simulate. Adopts [PR #11555](https://github.com/ethereum/EIPs/pull/11555) verbatim: `APPROVE_GUARANTEE = 0x4` scope, `compute_frame_sig_hash`, `guarantor_approved`, canonical paymaster guarantor mode with `bumpNonce`.
- **Keyed Nonces**: independent replay-protection sequences per `(sender, signer)`. Mirrors [EIP-8250](https://github.com/ethereum/EIPs/pull/11598) semantics (consumption inside the unique successful payment-scoped `APPROVE`, journaled outside revert and atomic-batch rollback, `KEYED_NONCE_FIRST_USE_GAS = 20000`). Diverges only in shape: one `uint64 signer` envelope field instead of `(nonce_key, nonce_seq)`, so the same identifier indexes the keyed nonce and the registered pubkey.
- **Signer Binding**: tx-scoped `verified_signers` table populated by non-secp256k1 `VERIFY` frames that prove `(digest, address)` against a registered pubkey. `ECRECOVER` consults the table on the hit path; miss path is byte-identical to upstream.

**Protocol additions**

- One envelope field: `signer` (uint64).
- One system contract: `AUTH_MANAGER` at a reserved address (EIP-4788 / EIP-2935 pattern). Holds keyed nonces and registered signers under one address.
- Zero new opcodes, zero new precompiles, zero account-RLP changes.

**Related PRs and alignment**

- [Guarantors (#11555)](https://github.com/ethereum/EIPs/pull/11555) by Derek Chiang — adopted verbatim where it touches our spec surface.
- [Keyed Nonces (EIP-8250, #11598)](https://github.com/ethereum/EIPs/pull/11598) by Thomas Thiery et al. — same consumption-on-payment-approval semantics, single-field envelope shape.
- [EIP-8164 Key Delegation](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md) — independent; not modified here.

Authors of those proposals are credited in the EIP `author` header.

# Expand EIP-8141 with Guarantors, Flexible Nonces, and Signer Binding

This PR replaces the previous consolidated proposal (PR #11643). The earlier draft bundled four additions on top of EIP-8141: guarantors, flexible nonces, signer binding, and an envelope `expiry` field. Upstream has since merged an in-spec **expiry verifier frame** at `EXPIRY_VERIFIER = address(0x8141)`, an 8-byte `frame.data` deadline covered by `compute_sig_hash` and dropped deterministically from the public mempool when expired. That mechanism subsumes every load-bearing property of the previous envelope-expiry design without spending an envelope byte on every tx that does not use a deadline. The envelope `expiry` field is therefore removed from this PR; deadline use-cases route through the upstream verifier frame.

The remaining three features are unchanged in intent from the previous PR.

**Features included:**

- **Guarantors**: payer primitive making txs public-mempool admissible even when sender validation may fail; enables ERC-20 paymaster repayment safely.
- **Flexible Nonces**: keyed nonce streams per sender; concurrent submission for privacy-pool withdrawals, recurring actions, and intents.
- **Signer Binding**: registry-only `(sender, signer) → (pubkey, type)`; spans secp256k1, lattice, multivariate, hash-based; inline pubkeys rejected.

**Protocol additions:**

- **One envelope field:** `signer` (uint64 registered-signer id).
- **One system contract:** `AuthManager` at a reserved address, following the EIP-4788 / EIP-2935 system-contract pattern, holding both keyed nonce streams and registered pubkey signers under one address.
- **Zero new opcodes.**
- **Zero new precompiles.**
- **Zero account RLP changes.**

**Relationship to prior PR (#11643)**

- Same three remaining features, same `AuthManager` shape, same reference contracts.
- Envelope shrinks from two added fields (`signer`, `expiry`) to one (`signer`); pre-frame consensus drops the expiry check.
- `TXPARAM(0x0E)` (expiry) is removed; `TXPARAM(0x0C)` (signer) and `TXPARAM(0x0D)` (pre-state legacy nonce) remain.
- Mempool RBF rules drop expired-eviction; `(sender, signer, nonce)` replacement is unchanged.
- Rationale "Deadlines via expiry verifier frame, not envelope" in the EIP body explains the drop and why a single deadline path through the spec is preferable.

**Related Proposals**

1. Guarantors: [PR #11555](https://github.com/ethereum/EIPs/pull/11555)
2. Keyed Nonces: [PR #11598](https://github.com/ethereum/EIPs/pull/11598)
3. Key Delegation: [EIP-8164](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md)

Authors of those proposals are credited in the `author` header.

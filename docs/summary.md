Extend EIP-8141 from just a new transaction type into a complete native AA upgrade by folding in the three downstream additions it needs to deliver on its premise.

**Features included:**

- **Guarantors**: payer primitive making txs public-mempool admissible even when sender validation may fail; enables ERC-20 paymaster repayment safely.
- **Flexible Nonces**: keyed nonce streams per sender; concurrent submission for privacy-pool withdrawals, recurring actions, and intents.
- **Signer Binding**: registry-only `(sender, signer) → (pubkey, type)`; spans secp256k1, lattice, multivariate, hash-based; inline pubkeys rejected.

Deadlines are covered by the upstream **expiry verifier frame** (`EXPIRY_VERIFIER = address(0x8141)`, merged in the current EIP-8141 spec). Earlier revisions added a redundant `expiry` envelope field; that has been dropped in favor of the upstream mechanism. Rationale in `eip-8141.md` under "Deadlines via expiry verifier frame, not envelope" and `docs/compare.md`.

**Protocol additions:**

- **One envelope field:** `signer` (uint64 registered-signer id).
- **One system contract:** `AuthManager` at a reserved address, like EIP-4788 / EIP-2935, holding keyed nonce streams and registered pubkey signers.
- **Zero new opcodes.**
- **Zero new precompiles.**
- **Zero account RLP changes.**

**Related Proposals**

1. Guarantors: [PR #11555](https://github.com/ethereum/EIPs/pull/11555)
2. Keyed Nonces: [PR #11598](https://github.com/ethereum/EIPs/pull/11598)
3. Key Delegation: [EIP-8164](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md)

Authors of those proposals are credited in the `author` header.

Extend EIP-8141 from just a new transaction type into a complete native AA upgrade by folding in the four downstream additions it needs to deliver on its premise.

**Features included:**

- **Guarantors**: payer primitive making txs public-mempool admissible even when sender validation may fail; enables ERC-20 paymaster repayment safely.
- **Flexible Nonces**: keyed nonce streams per sender; concurrent submission for privacy-pool withdrawals, recurring actions, and intents.
- **Signer Binding**: registry-only `(sender, signer_id) → (pubkey, type)`; spans secp256k1, lattice, multivariate, hash-based; inline pubkeys rejected.
- **Envelope Expiry**: protocol-enforced deadline via `expiry` envelope field; tx invalid when `block.timestamp >= expiry`; ready/expired only, no future-valid.

**Protocol additions:**

- **Two envelope fields:** `signer` (uint64 registered-signer id) and `expiry` (uint64 unix-seconds deadline).
- **One system contract:** `AuthManager` at a reserved address, like EIP-4788 / EIP-2935, holding keyed nonce streams and registered pubkey signers.
- **Zero new opcodes.**
- **Zero new precompiles.**
- **Zero account RLP changes.**

**Related Proposals**

1. Guarantors: [PR #11555](https://github.com/ethereum/EIPs/pull/11555)
2. Keyed Nonces: [PR #11598](https://github.com/ethereum/EIPs/pull/11598)
3. Key Delegation: [EIP-8164](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md)

Authors of those proposals are credited in the `author` header.

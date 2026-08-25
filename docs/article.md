# Rebase the Outcomes, Not the Old Mechanisms

EIP-8141 changed underneath this project. It gained a signature list, P256 validation, arbitrary signature witnesses, signature introspection, explicit execution/state gas, stricter atomic batches, and a much fuller public-mempool model. The old proposal's `signer` field, frame-specific hash, and `AuthManager` registry no longer fit that architecture.

The goals still hold.

Guarantors remain the cleanest way to relay accounts whose validation cannot be safely simulated by every public node. The rebase keeps the payer commitment and fallback replay nonce, but uses the canonical signature list instead of embedding a signature in frame data. Because empty-`msg` signature bytes are elided, sender and guarantor independently sign the same complete transaction.

[EIP-8164](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md) demonstrates the need for native alternative-key and post-quantum authentication, but Ethereum's immutable contract base still expects secp256k1-shaped `ECRECOVER` results. Signer binding carries that interoperability goal into EIP-8141: a binding frame lets account code validate an application digest with `SIGPARAM` or `SIGDATACOPY`, return the digest, and populate a transaction-scoped compatibility table. Unlike EIP-8164's persistent native-key designator, this mechanism persists neither the key nor the binding.

Parallel nonces now live directly in EIP-8141. The integrated ordered sets of full-width nonce keys preserve privacy-nullifier and multi-domain outcomes that the old single-signer stream discarded. EIP-8250 remains the design source, not a required companion activation.

EIP-8130 contributes a nonce-free sentinel backed by short expiry and bounded replay state. The lesson is not that nonce counters can simply disappear: the counter is replaced by a fee- and signature-invariant logical identifier plus a consensus ring buffer. The rebase now makes this a native EIP-8141 mode, with concrete storage, reorg, and EIP-8037 state-gas rules. Ethereum-specific expiry-window and capacity values remain a Draft activation gate.

The result is smaller where upstream became stronger and more explicit where the remaining compatibility gaps are real.

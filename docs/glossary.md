# Glossary

## Current EIP-8141

**Frame transaction.** EIP-8141 transaction composed of ordered `DEFAULT`, `VERIFY`, and `SENDER` frames.

**Signature entry.** Outer transaction object `[scheme, signer, msg, signature]`. Protocol-validated schemes currently include secp256k1 and P256; `ARBITRARY` carries account-validated witnesses.

**Canonical signature hash.** Hash over the full transaction with raw signature bytes elided for entries whose `msg` is empty.

**Expiry verifier frame.** Built-in `VERIFY` frame at `EXPIRY_VERIFIER` carrying an eight-byte signed deadline.

**Execution gas / state gas.** Independent per-frame budgets for computation/access and durable state growth.

**Validation prefix.** Shortest frame prefix whose successful execution sets the payer; the public mempool simulates or directly evaluates only this prefix.

## Rebased additions

**Guarantor.** Canonical paymaster that approves payment before sender validation and pays even if sender authentication fails.

**`APPROVE_GUARANTEE`.** Approval scope `0x4`. It escrows the maximum transaction cost without approving sender execution or consuming the sender's selected replay protection.

**Guarantor nonce.** Per-sender replay counter in the canonical paymaster, advanced by `bumpNonce` when sender validation fails.

**Signer binding.** Transaction-scoped authorization making `ECRECOVER(digest, ...)` return an account address after that account's binding frame validates and returns the digest.

**`SIGNER_BINDING_FLAG`.** Frame flag `0x10`, valid only on a standalone `VERIFY` frame with no approval scope.

**Verified-signers table.** Transaction-scoped `digest -> address` map capped at eight entries. It is populated from successful signer-binding frame return data.

**Approved scope.** Actual scope used by a completed frame's successful `APPROVE`, exposed as `FRAMEPARAM(0x0C)`.

## Native keyed nonces

**Nonce key set.** Strictly increasing list of one to sixteen `uint256` replay-domain keys sharing one `uint64 nonce_seq`.

**Legacy nonce key.** Singleton set `[0]`, which aliases the sender's account nonce.

**`NONCE_MANAGER`.** EIP-8141 system-contract state holding non-zero nonce-key sequences.

**Replay independence.** Property that consuming one non-zero key set does not advance a disjoint key set. It does not by itself remove balance or validation-state dependencies.

## Native nonceless mode

**`NONCE_KEY_MAX`.** Singleton EIP-8141 key-set sentinel `[2**256 - 1]` selecting counter-free mode.

**Replay identifier.** Fee- and raw-signature-invariant hash of the logical transaction used for nonceless deduplication and replacement.

**Replay buffer.** Fixed-capacity consensus ring plus live map holding `(sender, replay_id, expiry)` until expiry.

**`NONCELESS_REPLAY_MANAGER`.** EIP-8141 system account holding the domain-separated replay ring, cursor, and live map.

**Nonceless expiry window.** Consensus maximum between inclusion time and the required expiry-verifier deadline.

## Removed terminology

**`AuthManager`.** Removed local registry that coupled nonce streams and stored pubkeys. Replaced by native EIP-8141 keyed state for nonces and account-defined signature-list validation for signer binding.

**Keyed signer stream.** Removed coupling between one signer ID and one nonce. Current nonce keys and signature entries are independent.

**Frame signature hash.** Removed auxiliary hash that elided one frame's data. Current signature-list hashing makes it unnecessary.

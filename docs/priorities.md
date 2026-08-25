# Priorities

## Central claim

EIP-8141 succeeds when arbitrary account validation can reach the public mempool and remain useful across Ethereum's deployed contract base. New signature schemes alone are insufficient if immutable contracts recognize only `ECRECOVER` and if public relay rejects the account's validation logic.

The load-bearing outcomes are therefore:

1. **Public inclusion for arbitrary validation**, through guarantors.
2. **Legacy-contract interoperability**, through signer binding.
3. **Replay-domain independence**, natively in EIP-8141.
4. **Counter-free submission**, with bounded consensus replay state.

The mechanisms must follow current upstream architecture rather than preserve obsolete local shapes.

## Consolidated bundle

**Native keyed and nonceless nonce modes + guarantors + signer binding.** This is the consolidated EIP-8141 delta.

- Guarantors remove public-mempool simulation as the gate on sender validation.
- Signer binding lets P256, post-quantum, and account-defined authorization work with existing permit-style contracts.
- Guarantors and signer binding reuse the current signature list and frame introspection without adding persistent authorization state.
- Keyed nonce domains preserve independent transaction lanes and privacy nullifiers directly in the frame transaction.
- Nonceless mode preserves replay safety without counter coordination through bounded expiry and deterministic consensus replay state.

The only nonceless Draft gate is fixing the coupled L1 expiry-window and ring-capacity values from worst-case throughput benchmarks.

## Explicitly rejected

- Reintroducing `AuthManager` solely to preserve the old design.
- Tying every nonce domain to one registered signer.
- Inlining an envelope deadline alongside the expiry verifier.
- Treating transaction-hash deduplication as nonce-free replay protection.
- Treating nonceless capacity as a node-local policy value.

## Review order

1. Verify the upstream rebase is textually honest.
2. Verify guarantor failure, replay, payer override, and state-gas accounting.
3. Verify signer-binding authority, conflicts, and unchanged `ECRECOVER` misses.
4. Verify keyed nonce validation, state-gas charging, atomic consumption, and mempool identity.
5. Verify nonceless storage, reorg, and state-gas rules; then fix activation parameters with explicit worst-case bounds.

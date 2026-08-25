# Auth Scopes

_Maximum bundle, now represented by the consolidated draft._

## Bundle

Auth scopes combines:

- native EIP-8141 keyed nonce sets;
- transaction-scoped signer binding;
- guarantor-backed public-mempool admission;
- native nonceless `[NONCE_KEY_MAX]` mode;
- the existing EIP-8141 expiry verifier frame.

The stale version also added envelope expiry and routed keys and nonces through `AuthManager`. Both are removed. The expiry verifier already supplies deadlines, while EIP-8141's signature list and native nonce keys supply better surfaces for authorization and replay domains.

## Canonical position

Keyed nonces, guarantors, signer binding, and nonceless transactions are in the consolidated EIP-8141 draft. The nonceless storage layout, reorg behavior, and EIP-8037 state-gas ownership are specified; only the coupled L1 expiry-window and ring-capacity activation values remain pending benchmarks.

The components remain reviewable independently even though EIP-8141 is their normative owner.

## Review order

1. Review native keyed nonce validation, consumption, and state-gas accounting.
2. Review guarantor execution and replay fallback.
3. Review signer-binding authority and `ECRECOVER` compatibility.
4. Verify nonceless identity, storage, expiry, state-gas, and full-buffer behavior.
5. Benchmark and fix the L1 expiry-window and capacity values.

# Mempool Tiers

```
Canonical for:  restrictive / expansive / private tier vocabulary as used in this repo
Referenced by:  every alternative
```

_Reference for mempool-admission paths EIP-8141 transactions land in. Cited by every alternative. The [current spec](https://eip8141.io/current-spec#mempool-policy) is normative for the restrictive tier; [Mempool Strategy](https://eip8141.io/mempool-strategy) tracks the broader two-tier design._

EIP-8141 specifies the restrictive public-mempool tier. The website also tracks an expansive opt-in tier and private/direct-to-builder delivery for txs that remain consensus-valid but are not publicly gossipable.

| Tier | What it admits | Validation budget | What it forbids |
|---|---|---|---|
| **Restrictive** | Public-mempool default. Deterministic checks; bounded reads against system contracts. | ~100 000 gas validation prefix. | Shared-state reads not backed by a guarantor; environmental opcodes (`block.timestamp`, `block.number`) during validation; unbounded loops; arbitrary calldata-driven validation paths. |
| **Expansive** | Wider-mempool / opt-in propagation. Tolerates shared-state reads and environmental opcodes during validation. | Larger budget; node policy. | Some flows (e.g. validation that touches arbitrary contract storage) still routed away from public mempool. |
| **Private (direct-to-builder)** | Sent to specific builders out-of-band. No mempool propagation. | Builder-defined. | Nothing beyond what the builder enforces. |

## Why restrictive matters

Restrictive-tier admissibility is the goal for every primitive proposed in this repo. It is the only tier that propagates publicly without bundlers, without trusted relayers, and without the user having to know which builder to send to. Anything that drops a tx out of restrictive into expansive (or worse, private) is a UX cost: latency, fee competition, censorship resistance.

The design discipline behind every alternative is to keep its added flow restrictive-tier admissible. Where a feature inherently requires shared-state reads (e.g., guarantor-backed shared-state caveats), it ships paired with a guarantor commitment that re-classifies the validation as economic risk rather than mempool policy.

## Per-feature classification

| Flow | Tier |
|---|---|
| Flexible nonces, non-zero stream selector: one slot read on the active registry (`NonceManager.check(sender, nonce_key)` standalone, or `AuthManager.checkNonce(sender, signer)` aggregated) | Restrictive |
| Expiry verifier frame (upstream baseline): deadline carried as `frame.data` of a special VERIFY frame, dropped deterministically when `frame.data < now` | Restrictive |
| Envelope `expiry` field (Envelope-expiry alternative only): deterministic from envelope | Restrictive |
| Envelope `expiry` beyond node-policy horizon (Envelope-expiry alternative only) | Rejected (`expiry_too_far_future`) |
| Signer binding: one slot read on the active registry (`PubkeyRegistry.get` standalone, or `AuthManager.getSigner` in aggregated proposals) | Restrictive (PQ verify gas absorbed by 100 k prefix once stage-2 PQ precompiles ship; expansive before then) |
| Guarantors: guarantor VERIFY restrictive; sender-VERIFY simulation skippable | Restrictive |

## Restrictive-tier reads each feature adds

| Feature | New restrictive-tier reads |
|---|---|
| Flexible nonces | Standalone: one slot per touched `(sender, nonce_key)` stream on `NonceManager`. Aggregated: one slot per touched `(sender, signer)` stream on `AuthManager`. |
| Signer binding | One slot per binding VERIFY frame on `PubkeyRegistry`. |
| Expiry verifier frame (upstream baseline) | None (pure envelope-deterministic deadline read from `frame.data`). |
| Envelope `expiry` (Envelope-expiry alternative only) | None (pure envelope check). |
| Guarantors | Guarantor's own VERIFY must itself fit restrictive-tier rules. |

Aggregated alternatives (`key-streams`, `auth-scopes`) sum the above. Both reads land on `AuthManager` instead of two separate registries; cost is identical (one slot per side).

## Caps that protect restrictive admission

- `MAX_ACTIVE_STREAMS_PER_SENDER = 16` (Flexible nonces standalone) / `MAX_ACTIVE_SIGNERS_PER_SENDER = 16` (aggregated): bounds non-zero-stream txs per sender in public mempool.
- `MAX_BOUND_SIGNERS = 8` (signer binding): bounds verified-signers-table population per tx.
- In the Envelope-expiry alternative only: node-policy upper bound on `expiry - now` (e.g. 7 days); submissions beyond this are rejected with `expiry_too_far_future`. The consolidated EIP does not include this cap because deadlines live in `frame.data` of the upstream expiry verifier frame and the existing per-frame structural rules already bound them. Expired txs are dropped on each new head in both cases.

## Block-invalidation and RBF

Both rules cut across tiers and apply identically:

- **RBF**: matches `(sender, stream_selector, tx.nonce)` where `stream_selector` is `nonce_key` (standalone) or `signer` (aggregated). In the Envelope-expiry alternative only, the replacement must additionally satisfy its own `expiry`.
- **Block-invalidation**: when a block increments any `(sender, stream_selector)` stream, pending txs at the pre-increment sequence on that stream are invalidated.

## FOCIL note

FOCIL (the inclusion-list mechanism) places attester-facing constraints on mempool determinism. Every restrictive-tier flow described here is FOCIL-friendly by construction: deterministic from envelope or one bounded storage read, no environmental opcodes during validation. Cross-client tests on per-stream RBF are a known follow-up. The expiry verifier frame is FOCIL-friendly for the same reason: deadlines are carried in `frame.data` covered by `compute_sig_hash`, with `TIMESTAMP` permitted only inside that frame's canonical runtime.

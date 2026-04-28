# Mempool Tiers

```
Canonical for:  restrictive / expansive / private tier vocabulary as used in this repo
Referenced by:  every Phase-1 alternative; P2
```

_Reference for the mempool-admission tiers EIP-8141 transactions land in. Cited by every Phase-1 alternative; Phase-2 permissions also slots into this taxonomy. EIP-8141 is the normative source; this doc collects the parts proposals depend on._

EIP-8141 defines three admission tiers for tx propagation. They differ in what a mempool node is allowed to evaluate during validation, which determines what kinds of frames a tx can carry and still be gossiped publicly.

| Tier | What it admits | Validation budget | What it forbids |
|---|---|---|---|
| **Restrictive** | Public-mempool default. Deterministic checks; bounded reads against system contracts. | ~100 000 gas validation prefix. | Shared-state reads not backed by a guarantor; environmental opcodes (`block.timestamp`, `block.number`) during validation; unbounded loops; arbitrary calldata-driven validation paths. |
| **Expansive** | Wider-mempool / opt-in propagation. Tolerates shared-state reads and environmental opcodes during validation. | Larger budget; node policy. | Some flows (e.g. validation that touches arbitrary contract storage) still routed away from public mempool. |
| **Private (direct-to-builder)** | Sent to specific builders out-of-band. No mempool propagation. | Builder-defined. | Nothing beyond what the builder enforces. |

## Why restrictive matters

Restrictive-tier admissibility is the goal for every primitive proposed in this repo. It is the only tier that propagates publicly without bundlers, without trusted relayers, and without the user having to know which builder to send to. Anything that drops a tx out of restrictive into expansive (or worse, private) is a UX cost: latency, fee competition, censorship resistance.

The design discipline behind every Phase-1 alternative is to keep its added flow restrictive-tier admissible. Where a feature inherently requires shared-state reads (e.g., guarantor-backed shared-state caveats), it ships paired with a guarantor commitment that re-classifies the validation as economic risk rather than mempool policy.

## Per-feature classification

| Flow | Tier |
|---|---|
| 2D nonces (`nonce_key > 0`): `NonceLaneRegistry.check` is one slot read | Restrictive |
| Validity windows: `valid_after`, `valid_before` deterministic from envelope | Restrictive |
| Validity windows beyond tier horizon | Expansive (24 h) or direct-to-builder (unlimited) |
| Signer binding: `PubkeyRegistry.get` is one slot read | Restrictive (PQ verify gas absorbed by 100 k prefix once stage-2 PQ precompiles ship; expansive before then) |
| Guarantors: guarantor VERIFY restrictive; sender-VERIFY simulation skippable | Restrictive |
| Phase-2 permissions, one-hop canonical-caveat execution-only | Restrictive |
| Phase-2 permissions, canonical caveat with shared-state read | Expansive (manager-as-guarantor would re-classify; that's v2) |
| Phase-2 permissions, arbitrary caveats, re-delegation, stateful caveats | Expansive / private |

## Restrictive-tier reads each Phase-1 feature adds

| Feature | New restrictive-tier reads |
|---|---|
| 2D nonces | One slot per touched `(sender, nonce_key)` lane on `NonceLaneRegistry`. |
| Signer binding | One slot per binding VERIFY frame on `PubkeyRegistry`. |
| Validity windows | None (pure envelope check). |
| Guarantors | Guarantor's own VERIFY must itself fit restrictive-tier rules. |

Aggregated alternatives (`key-lanes`, `authorization-scopes`) sum the above.

## Caps that protect restrictive admission

- `MAX_ACTIVE_STREAMS_PER_SENDER = 16` (2D nonces): bounds non-zero-key txs per sender in public mempool.
- `MAX_BOUND_SIGNERS = 8` (signer binding): bounds verified-signers-table population per tx.
- Tiered validity-window deferral (validity windows): public mempool 1 h; expansive 24 h; direct-to-builder unlimited.
- `GOSSIP_THRESHOLD = 60 s` (validity windows): future-valid txs held locally until within threshold of `valid_after`.

## Block-invalidation and RBF

Both rules cut across tiers and apply identically:

- **RBF**: matches `(sender, nonce_key, tx.nonce)`. Replacement must satisfy its own validity window if windows are in scope.
- **Block-invalidation**: when a block increments any `(sender, nonce_key)` lane, pending txs at the pre-increment sequence on that lane are invalidated.

## FOCIL note

FOCIL (the inclusion-list mechanism) places attester-facing constraints on mempool determinism. Every restrictive-tier flow described here is FOCIL-friendly by construction: deterministic from envelope or one bounded storage read, no environmental opcodes during validation. Cross-client tests on per-lane RBF and the lane + window interaction in aggregated alternatives are a known follow-up.

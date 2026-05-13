# Envelope Expiry for EIP-8141

```
Status:             research draft
Depends on:         EIP-8141 + guarantors
Introduces:         expiry envelope field
Shared appendices:  mempool-tiers, sighash-binding
```

## 1. Status and scope

Individual alternative. Adds a single protocol-level expiration field so time-bounded transactions propagate through the public (restrictive) mempool instead of expansive or private tiers. The field is `expiry`: a unix-seconds deadline past which a tx is consensus-invalid. There is no lower bound. Constraints respected (no new opcodes, precompiles, frame modes, system contracts, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md). The sibling alternative [`validity-windows.md`](validity-windows.md) carries both `valid_after` and `valid_before`; this proposal argues that only the upper bound earns its envelope cost (§3).

## 2. Motivation

The user-visible problem is broader than swap deadlines. Once a tx envelope carries a deadline that consensus enforces, the public mempool becomes a usable substrate for time-bounded user intent. Today every category below invents its own offchain timing layer:

- **Intent-style flows.** Intent-based protocols (signed-order DEXes, cross-chain bridges, RFQ aggregators, gasless swaps) carry a deadline inside an offchain message a filler is supposed to respect; the protocol has no view of it. Envelope `expiry` collapses the timing layer into the tx itself, so no filler can stall a signed intent past its deadline and still land it on-chain.
- **Trading and MEV-sensitive submission.** "Land in the next n seconds or fail" is the dominant pattern for swap routers, liquidations, and any price-sensitive flow. Today wallets either send privately (losing public-mempool propagation) or accept stale execution.
- **Cross-chain swaps and HTLCs.** Atomic swaps rely on per-side deadlines, enforced today by a contract reading `block.timestamp`, which drops the tx out of restrictive-tier admission.
- **Async user actions in general.** Scheduled payments, conditional execution, wallet-to-wallet recovery: anything with a shelf life. The envelope is the right shape because shelf life is a property of the tx, not of any frame inside it.

Moving the bound into the envelope, checked once at tx entry, lets the tx propagate publicly without simulating any frame. One check, every node, no trust assumption.

## 3. Why one field, not two

The sibling alternative [`validity-windows.md`](validity-windows.md) ships both `valid_after` and `valid_before`. Both halves are envelope bytes every transaction in every block on every node pays for in propagation, witness inclusion, and state-witness reads. As gas demand grows, the marginal cost of an extra envelope field is paid by every tx, not just the ones using it. The test is not "is the field cheap individually?" but "does it carry its weight against every tx that doesn't use it?"

The two halves do not earn that weight equally. `valid_before` (deadlines) covers every use-case enumerated in §2, with protocol enforcement collapsing filler honesty about timing into a consensus rule. `valid_after` (scheduled activation) is a minority use-case solvable offchain: a wallet or service holding a signed tx can delay submission until the activation time. The "ship a tx now that nodes hold for an hour" pattern saves the signer one round-trip but costs every node mempool buffer space, a deferral horizon, a gossip-threshold rule, and an envelope field every other tx pays for.

The head-to-head against Validity windows comes down to four asymmetric costs:

| Axis | Validity windows (two-sided) | Envelope expiry (one-sided) |
|---|---|---|
| Envelope bytes paid by every tx | 2 `uint64` | 1 `uint64` |
| Mempool states | 4 (future-valid, ready, expired, reverse-invalid) | 2 (ready, expired) |
| Node policy surface | deferral horizon, gossip threshold, per-sender future-valid caps | expired eviction on new head |
| Error codes | 4 | 2 |

Conclusion: keep the field that earns its envelope cost (`valid_before`), drop the one that does not (`valid_after`), and name the survivor `expiry` to match the vocabulary every wallet, contract, and offchain protocol already uses. Scheduled activation does not vanish from user vocabulary; it moves back to the layer that can absorb it without taxing every tx.

## 4. Priorities and non-goals

Priorities:

1. Protocol-level, not VERIFY-level. Keep the restrictive tier admissible.
2. First-class 8141 primitive, not inherited from ERC-4337's UserOperation payload.
3. Timestamp-based, not block-number-based.
4. One envelope field, not two.

Non-goals:

- Future-valid / scheduled activation (handled offchain by deferring submission; covered by Validity windows if that alternative is preferred).
- Block-number bounds.
- Recurring / cron execution.
- On-chain schedulers.

## 5. Single-line spec delta

Add envelope field `expiry: uint64` (unix seconds; zero = no bound). Consensus rejects any tx included when `block.timestamp >= expiry`.

## 6. Normative spec

### Envelope

```
[chain_id, nonce, sender, frames, fees..., blob_versioned_hashes,
 expiry]
```

- `expiry: uint64`, unix seconds. Zero = no upper bound. For `expiry > 0`, tx invalid unless `block.timestamp < expiry`.

The field is covered by existing `compute_sig_hash` (Class A binding; see [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)). MUST NOT add a sighash rule change.

### Pre-tx consensus check (MUST)

```
if expiry != 0 and block.timestamp >= expiry: invalid
```

Bound exclusive. A tx in a block whose timestamp is at or past `expiry` is invalid; the block is invalid if it includes such a tx.

## 7. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

Two states are deterministic from the envelope (nodes don't simulate any frame, which is why restrictive-tier admission works): **ready** (`expiry == 0` or `block.timestamp < expiry`), **expired** (`block.timestamp >= expiry`).

### Consensus-relevant (MUST)

- **Inclusion validity:** the pre-tx check in §6 is a consensus rule. A tx in a block whose timestamp is at or past its `expiry` is invalid; the block is invalid if it includes such a tx.

### Node policy (SHOULD)

- **RBF:** applies; replacement MUST also satisfy its own `expiry` (consensus enforces).
- **Expired txs:** dropped on each new head.

## 8. RPC and wallet surface

Two canonical error codes at JSON-RPC `-32010..-32011`:

| Name | Code | Meaning |
|---|---|---|
| `expiry_already_passed` | -32010 | `expiry != 0` and `expiry <= block.timestamp` at admission |
| `expiry_too_far_future` | -32011 | `expiry - now` exceeds a node-policy upper bound |

Wallet display (non-normative):

- Local-time equivalent alongside the timestamp.
- Relative duration ("expires in 2 minutes").
- Warn on unusually long expirations.
- Warn on already-passed expirations before signing.
- Hardware wallets parse the envelope field natively.

## 9. Security and DoS analysis

- **No future-valid buffer.** Dropping `valid_after` removes the future-valid mempool state; every tx is either ready or expired. Nodes do not buffer signed-but-not-yet-valid txs, so a sender cannot use the mempool as scheduled-tx storage.
- **Replay against expired signatures.** A signed tx with `expiry` set is no longer includable past that timestamp; replaces ad-hoc deadline parsing in app contracts.
- **MEV / auction contention.** Tight `expiry` lets wallets express "land in the next n seconds or fail," reducing stale execution after market moves.
- **Intent-system collusion resistance.** A filler holding a signed intent past its deadline cannot submit it: consensus rejects the tx. Intent-system safety stops depending on filler honesty about timing.

## 10. Compatibility and interactions

- **Sighash binding:** resolved by envelope placement (Class A; see [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)).
- **Guarantors:** expired txs drop from mempool; guarantor doesn't pay for non-includable txs.
- **Flexible nonces / signer binding:** orthogonal. Expiry runs before any frame.
- **FOCIL:** deterministic from envelope, attester-visible, no simulation required.
- **vs. Validity windows:** strict subset on consensus surface and node policy; loses the future-valid mempool state and the `valid_after` field. The two are mutually exclusive in a single upgrade. Trade-off argued in §3.
- **vs. ERC-4337:** 4337's `validUntil` lives in UserOperation payload, enforced by bundlers; protocol nodes have no view. This proposal moves the primitive down into the protocol.
- **vs. VERIFY-frame workaround:** works on-chain but fails publicly because `block.timestamp` reads drop txs into expansive/private tiers.
- **vs. intent systems:** consensus enforces the deadline on the settlement tx itself; intent protocols keep the offchain matching layer but stop having to police filler timing.

## 11. Open questions

None block this proposal. Node-policy upper bound for `expiry - now` (e.g., 7 days) is tunable post-shipping.

## 12. Appendix references

- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A binding (envelope placement).
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.

## 13. EIP-ready delta

1. Add envelope field `expiry: uint64`; zero = no bound.
2. Consensus check at tx entry: `block.timestamp >= expiry` is invalid.
3. Mempool: RBF replacement MUST satisfy its own `expiry`; expired eviction on new head.
4. Two JSON-RPC error codes at `-32010..-32011`.
5. Wallet-display appendix (non-normative).

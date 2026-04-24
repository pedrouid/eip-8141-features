# Validity Windows for EIP-8141

*Author: Claude. Scratch doc, not indexed on the site.*

This proposal adds protocol-level validity-window support to EIP-8141 so that time-bounded transactions work on the public (restrictive) mempool instead of being pushed to expansive/private tiers.

---

## Direct answers to the open questions

> *Does EIP-8141 have an equivalent to `validUntil`/`validAfter` at the protocol level?*

**Today: no.** The spec has no envelope-level time bound. The only workaround is a VERIFY frame that reads `block.timestamp` (or `block.number`) and reverts outside a window.

> *If I need time-bounded validity, which mempool tier do I end up in?*

**Today: expansive or private.** The VERIFY-frame workaround uses environmental opcodes during validation, which the restrictive tier forbids (the restriction exists to preserve VOPS compatibility — see `mempool-strategy.md`). Time-bounded txs therefore can't propagate publicly today.

**With this proposal: restrictive.** Validity bounds move out of VERIFY and into the tx envelope, checked once at tx entry by consensus. No environmental opcode runs during validation, so the restrictive tier admits time-bounded txs cleanly.

---

## Priorities

1. **Protocol-level, not VERIFY-level.** The whole point is to keep the restrictive tier admissible.
2. **No new opcodes. No new precompiles. No new frame modes.**
3. **Match Tempo's object model** where it's already the right shape (two fields, inclusive/exclusive bounds). Tempo is the clean-slate precedent; follow it.
4. **First-class 8141 primitive**, not inherited from contract-era ERC-4337 (where `validUntil`/`validAfter` live in the UserOperation payload and rely on bundler enforcement).
5. **Timestamp-based, not block-number-based.** Wallet UX is cleaner, ERC-4337 already uses timestamps, post-merge clock drift is bounded, and the unit is what users actually mean.

---

## 1. Single-line spec delta

> **Add two envelope fields `valid_after: uint64` and `valid_before: uint64` (both unix timestamps in seconds, zero = no bound). Consensus rejects any tx included when `block.timestamp` falls outside `[valid_after, valid_before]`.**

No opcode, no precompile, no new frame machinery. One consensus check at tx entry.

---

## 2. Envelope additions

```
[chain_id, nonce_key, nonce, sender, frames, max_priority_fee_per_gas,
 max_fee_per_gas, max_fee_per_blob_gas, blob_versioned_hashes,
 valid_after, valid_before]
```

Two new fields, both `uint64`, both unix-timestamp seconds:

- `valid_after`: **zero means no lower bound.** For `valid_after > 0`, tx is invalid unless `block.timestamp > valid_after`.
- `valid_before`: **zero means no upper bound.** For `valid_before > 0`, tx is invalid unless `block.timestamp < valid_before`.

Zero is the no-bound sentinel for both fields, unambiguously. The earlier "always expired when `valid_before == 0`" framing is removed — there is no degenerate interpretation.

**Reverse-window rule.** If both fields are non-zero and `valid_after >= valid_before`, the tx is consensus-invalid. A reverse finite window is a dead-on-arrival signature.

Both fields are covered by the existing `compute_sig_hash` (envelope fields, not VERIFY calldata). No sighash rule change.

---

## 3. Consensus check

At tx entry, before any frame executes:

```
if valid_after != 0 and block.timestamp <= valid_after: invalid
if valid_before != 0 and block.timestamp >= valid_before: invalid
if valid_after != 0 and valid_before != 0 and valid_after >= valid_before: invalid
```

Bounds are exclusive on both ends (strictly greater than `valid_after`, strictly less than `valid_before`). A tx landed in a block whose timestamp violates either bound is invalid. No frame runs, no gas is charged, the block is invalid if it includes the tx.

---

## 4. Mempool semantics

Three states for a pending tx:

- **Future-valid** — `block.timestamp <= valid_after`. The tx is not yet eligible. Mempool holds it as deferred; does not gossip it as ready.
- **Ready** — inside the window. Normal gossip, readiness, and RBF rules apply.
- **Expired** — `block.timestamp >= valid_before`. Tx is invalid for inclusion; drop from mempool.

**Readiness is fully deterministic from the envelope** — nodes don't simulate any frame to decide whether a tx is admissible. This is why the restrictive tier can accept time-bounded txs under this proposal but couldn't before.

### Node policy (not consensus)

To prevent DoS via far-future txs sitting in mempool:

- **Tiered deferral horizon**:
  - Public (restrictive) mempool admits txs with `valid_after - now <= 1 hour`.
  - Expansive tier admits up to `24 hours`.
  - Direct-to-builder has no horizon cap.
  Txs beyond a tier's horizon fail admission at that tier with `validity_window_too_far_future` and route through higher tiers.
- **Gossip threshold**: future-valid txs are held locally and not gossiped until within `GOSSIP_THRESHOLD = 60 seconds` (5 slots) of `valid_after`. Bounds bandwidth cost without risking propagation gaps.
- **Max pending future-valid txs per sender**, e.g., 16. Prevents a single account from flooding mempool state with far-out txs.
- **Replacement while future-valid**: RBF still applies; a replacement must also satisfy its own validity window.
- **Expired txs are dropped immediately** on each new head. No RBF opportunity after expiry.

---

## 5. Unit choice: timestamp, not block number

Block-number bounds were considered and rejected:

| | Timestamp | Block number |
|---|---|---|
| Wallet UX | "valid for 10 minutes" maps directly | "valid for ~50 blocks" requires mental arithmetic |
| Client determinism | Post-merge, block.timestamp is deterministic per slot (12s) | Deterministic |
| Congestion drift | None — 12s slots don't drift | Significant; block rate varies with slot skips / missed slots |
| Prior art | ERC-4337 uses timestamps | None common in envelope-level validity |
| Tempo | (Not committed in the current gist) | — |

Timestamp wins on UX, matches ERC-4337's conventions, and has no meaningful determinism downside post-merge.

---

## 6. Interaction with the other primitives and proposals

### Sighash binding

No change needed. `valid_after` and `valid_before` are envelope fields, so the existing sighash covers them for free. This is the same argument that made the 2D-nonces envelope approach correct.

### Execution authority

Orthogonal. A delegated tx can have validity windows; the delegator's offchain delegation `expiry` (signed into the delegation digest) and the tx envelope's `valid_before` are independent bounds. Caveat design can rely on envelope-level bounds being protocol-enforced, which is stronger than an offchain expiry.

### Guarantors

Mostly unaffected, with one clarification: if a tx expires between mempool admission and block inclusion, the mempool drops it; guarantor commitment is voided because the tx is no longer consensus-valid. Guarantors don't pay for expired txs because expired txs can't be included.

### 2D nonces

Orthogonal. A future-valid tx on stream `k` doesn't block later-sequenced txs on stream `j`. A future-valid tx on stream `k` *does* block the subsequent position on stream `k` (by definition — it owns that position until it resolves or expires). If the tx expires without landing, the sender can re-sign the next sequence on that stream.

### Permissions

Delegation bundles carry their own `expiry` inside the signed digest (separate layer, enforced by the manager). Envelope-level `valid_before` adds a *protocol-enforced* outer bound on when the redemption tx itself is valid. Both layers are useful: the delegation's expiry bounds the authority; the tx's validity window bounds the specific redemption attempt.

---

## 7. Use cases

1. **Time-sensitive intents.** "Submit this swap but only if it lands in the next 90 seconds." Common for MEV-sensitive flows and auction-style settlement.
2. **Scheduled execution.** "This tx is valid only after 09:00 tomorrow." Subscription payments, payroll, scheduled transfers.
3. **Implicit cancellation.** A user can revoke a signed tx by submitting a replacement with a tighter window (narrower `valid_before`).
4. **Session keys with hard expiry.** Even if a delegation's offchain expiry is long, individual redemption txs can be tightly bounded.
5. **Auction / commit-reveal.** Reveal txs valid only after a commit phase closes.

---

## 8. Comparison

- **vs. Tempo** — Tempo has `valid_after` / `valid_before` natively in the `0x76` envelope. EIP-8141 adopts the same shape. Both are native transaction designs and converge on the same primitive for the same reason — time-bound validity belongs at the protocol layer.
- **vs. ERC-4337** — 4337's `validUntil` / `validAfter` live in the UserOperation payload and are enforced by the EntryPoint + bundlers. Protocol nodes have no view of them. This proposal moves the primitive down into the protocol so the public mempool can reason about it directly without a bundler layer. The design here does not inherit from 4337.
- **vs. the VERIFY-frame workaround** — The workaround works on-chain but fails publicly because `block.timestamp` reads drop txs into expansive/private tiers. This proposal is strictly more expressive *and* more restrictive-tier-friendly.

---

## 9. Non-goals

- **Block-number bounds** — timestamp suffices; adding both would double the field surface for no UX gain.
- **Recurring / cron-style execution** — separate problem, outside this proposal's scope.
- **On-chain scheduler contracts** — an application-layer concern; validity windows enable but don't specify them.
- **Reverse windows** are handled in §3 as a consensus-invalid case (already covered as a normative rule above).

---

## 10. RPC error codes

Four canonical error names at JSON-RPC codes `-32010..-32013`:

| Name | Code | Meaning |
|---|---|---|
| `validity_window_too_far_future` | -32010 | `valid_after` beyond the node's tier deferral horizon. |
| `validity_window_not_yet_valid` | -32011 | `valid_after` in the future at a node that doesn't buffer future-valid txs. |
| `validity_window_already_expired` | -32012 | `valid_before <= block.timestamp`. |
| `validity_window_reverse` | -32013 | `valid_after >= valid_before` (both non-zero). |

Descriptive snake_case so wallets can render user-safe messages; contiguous block inside the JSON-RPC server-error reserved range.

---

## 11. Wallet display guidance (non-normative appendix)

Wallets surfacing validity windows to users should:

- **Render local-time equivalents** alongside the unix timestamps.
- **Show relative duration** ("valid for 2 minutes," "valid in 5 hours").
- **Warn on unusually long windows** (> 1 hour for interactive txs; thresholds are wallet-specific).
- **Warn on already-expired or reverse windows** before signing — don't just rely on consensus rejection.
- **For scheduled transactions**, surface "not valid before &lt;time&gt;" prominently.
- **On hardware wallets**, parse both envelope fields natively and show the window on-device.

---

## 12. Spec delta summary

Against the current EIP-8141 draft:

1. Add envelope fields `valid_after: uint64` and `valid_before: uint64`, with zero as the no-bound sentinel for both (unambiguous).
2. Consensus check at tx entry: strict `>` for lower bound, strict `<` for upper bound. Reverse windows (both non-zero, `valid_after >= valid_before`) are consensus-invalid.
3. Mempool policy: tiered deferral horizon (1 h public / 24 h expansive / unlimited direct-to-builder), `GOSSIP_THRESHOLD = 60 s`, RBF while future-valid, expired-tx eviction on each new head.
4. Four JSON-RPC error codes at `-32010..-32013` for tx-rejection reasons.
5. Non-normative wallet-display guidance appendix.
6. No sighash rule change (envelope fields already covered).
7. No new opcode. No new precompile. No new frame mode.

**Net result:** time-bounded transactions become a public-mempool primitive, matching Tempo's capability without adopting Tempo's tx-type shape. The "which mempool tier?" answer flips from "expansive/private" to "restrictive," and EIP-8141 closes one of the most common gaps flagged against it by wallet and intent infrastructure teams.

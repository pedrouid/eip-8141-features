# Validity Windows for EIP-8141

_Scratch doc, not indexed on the site._

Adds protocol-level validity-window support to EIP-8141 so time-bounded transactions propagate through the public (restrictive) mempool instead of expansive/private tiers.

## Answers to the open questions

> _Does EIP-8141 have an equivalent to `validUntil`/`validAfter` at the protocol level?_

**Today: no.** The only workaround is a VERIFY frame reading `block.timestamp` and reverting outside a window.

> _If I need time-bounded validity, which mempool tier do I end up in?_

**Today: expansive or private.** The VERIFY workaround uses environmental opcodes during validation, which the restrictive tier forbids to preserve VOPS compatibility.

**With this proposal: restrictive.** Bounds move into the tx envelope, checked once at tx entry. No environmental opcode runs during validation.

## Priorities

1. Protocol-level, not VERIFY-level. Keep the restrictive tier admissible.
2. No new opcodes, precompiles, or frame modes.
3. Match Tempo's object model where it's the right shape.
4. First-class 8141 primitive, not inherited from ERC-4337's UserOperation payload.
5. Timestamp-based, not block-number-based. Wallet UX is cleaner; post-merge drift is bounded.

## 1. Single-line spec delta

> Add envelope fields `valid_after: uint64` and `valid_before: uint64` (unix seconds; zero = no bound). Consensus rejects any tx included when `block.timestamp` falls outside `(valid_after, valid_before)`.

No opcode, no precompile, no new frame machinery.

## 2. Envelope additions

```
[chain_id, nonce_key, nonce, sender, frames, fees...,
 blob_versioned_hashes, valid_after, valid_before]
```

- `valid_after: uint64` — **zero means no lower bound.** For `valid_after > 0`, tx invalid unless `block.timestamp > valid_after`.
- `valid_before: uint64` — **zero means no upper bound.** For `valid_before > 0`, tx invalid unless `block.timestamp < valid_before`.

Zero is the no-bound sentinel for both fields, unambiguously.

**Reverse-window rule.** If both fields are non-zero and `valid_after >= valid_before`, the tx is consensus-invalid.

Both fields covered by existing `compute_sig_hash`; no sighash rule change.

## 3. Consensus check

At tx entry, before any frame executes:

```
if valid_after != 0 and block.timestamp <= valid_after: invalid
if valid_before != 0 and block.timestamp >= valid_before: invalid
if valid_after != 0 and valid_before != 0 and valid_after >= valid_before: invalid
```

Bounds exclusive on both ends. A tx in a block whose timestamp violates either bound is invalid; the block is invalid if it includes such a tx.

## 4. Mempool semantics

Three states: **future-valid** (`block.timestamp <= valid_after`; deferred, not gossiped yet), **ready** (inside window; normal gossip/RBF), **expired** (`block.timestamp >= valid_before`; dropped).

Readiness is fully deterministic from the envelope — nodes don't simulate any frame. This is why restrictive-tier admission works.

### Node policy (not consensus)

- **Tiered deferral horizon**: public mempool admits `valid_after - now <= 1 hour`; expansive tier up to 24 hours; direct-to-builder unlimited. Beyond a tier's horizon fails with `validity_window_too_far_future`.
- **Gossip threshold**: future-valid txs held locally until within `GOSSIP_THRESHOLD = 60 seconds` (5 slots) of `valid_after`, then gossiped.
- **Max pending future-valid txs per sender**: e.g., 16.
- **RBF while future-valid**: applies; replacement must also satisfy its own validity window.
- **Expired** txs dropped immediately on each new head.

## 5. Unit choice: timestamp

Wallet UX: "valid for 10 minutes" maps directly; block-number requires mental arithmetic. Post-merge `block.timestamp` is deterministic per slot (12 s). ERC-4337 uses timestamps. Block-number rate drifts with missed slots.

## 6. Interaction with other primitives

- **Sighash binding**: resolved by envelope placement.
- **Execution authority**: orthogonal. Delegation's offchain `expiry` and envelope `valid_before` are independent bounds.
- **Guarantors**: if a tx expires between admission and inclusion, mempool drops it; guarantor doesn't pay for non-includable txs.
- **2D nonces**: orthogonal. A future-valid tx holds its stream position until it lands or expires; doesn't block other streams.
- **Permissions**: complementary. Delegation bundles carry application-layer `expiry`; envelope `valid_before` bounds each redemption attempt at the protocol layer. Both useful.

## 7. Use cases

- **Time-sensitive intents**: "land in the next 90 seconds." MEV-sensitive flows, auctions.
- **Scheduled execution**: "valid only after 09:00 tomorrow." Subscriptions, payroll.
- **Implicit cancellation**: replacement with tighter `valid_before` revokes an old signature.
- **Session keys with hard expiry**: individual redemption bounded even if delegation expiry is long.
- **Commit-reveal**: reveal txs valid only after commit phase closes.

## 8. Comparison

- **vs. Tempo**: same shape, same reasoning. Both native designs converge on envelope-level validity.
- **vs. ERC-4337**: 4337's `validUntil`/`validAfter` live in UserOperation payload, enforced by bundlers. Protocol nodes have no view. This proposal moves the primitive down into the protocol. No inheritance from 4337.
- **vs. VERIFY-frame workaround**: works on-chain but fails publicly because `block.timestamp` reads drop txs into expansive/private tiers.

## 9. Non-goals

- Block-number bounds.
- Recurring / cron execution.
- On-chain schedulers.
- Reverse windows: handled in §3 as consensus-invalid.

## 10. RPC error codes

Four canonical names at JSON-RPC `-32010..-32013`:

| Name | Code | Meaning |
|---|---|---|
| `validity_window_too_far_future` | -32010 | `valid_after` beyond tier horizon |
| `validity_window_not_yet_valid` | -32011 | `valid_after` future, node doesn't buffer |
| `validity_window_already_expired` | -32012 | `valid_before <= block.timestamp` |
| `validity_window_reverse` | -32013 | `valid_after >= valid_before` (both non-zero) |

## 11. Wallet display (non-normative)

- Local-time equivalents alongside timestamps.
- Relative duration ("valid for 2 minutes").
- Warn on unusually long windows.
- Warn on already-expired or reverse windows before signing.
- For scheduled txs, surface "not valid before &lt;time&gt;" prominently.
- Hardware wallets parse both envelope fields natively.

## 12. Spec delta summary

1. Add envelope fields `valid_after: uint64`, `valid_before: uint64`; zero = no bound for both.
2. Consensus check at tx entry: strict `>` lower, strict `<` upper. Reverse windows invalid.
3. Mempool: tiered deferral horizon (1 h / 24 h / unlimited), `GOSSIP_THRESHOLD = 60 s`, RBF while future-valid, expired eviction on new head.
4. Four JSON-RPC error codes at `-32010..-32013`.
5. Wallet-display appendix (non-normative).
6. No sighash rule change. No opcode, no precompile, no new frame mode.

Time-bounded transactions become a public-mempool primitive, matching Tempo's capability without adopting Tempo's tx-type shape. The "which mempool tier?" answer flips from expansive/private to restrictive.

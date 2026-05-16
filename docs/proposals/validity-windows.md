# Validity Windows for EIP-8141

```
Status:             SUPERSEDED for the upper bound by upstream expiry verifier frame; comparison only
Depends on:         EIP-8141 + guarantors
Introduces:         valid_after envelope field, valid_before envelope field (not adopted by the consolidated EIP)
Shared appendices:  mempool-tiers, sighash-binding
```

> **Note.** Upstream EIP-8141 merged an in-spec **expiry verifier frame** at `EXPIRY_VERIFIER = address(0x8141)` which subsumes the `valid_before` (upper-bound) half of this proposal. The `valid_after` (scheduled-activation) half is intentionally out of scope for the consolidated EIP because future-valid behavior is solvable offchain by deferring submission and would impose mempool buffering, per-sender caps, and gossip-threshold rules on every node. The consolidated [`/eip-8141.md`](../../EIPS/eip-8141.md) does NOT carry validity-window envelope fields. This proposal is preserved as comparison surface only.

## 1. Status and scope

Individual alternative. Adds protocol-level validity-window support so time-bounded transactions propagate through the public (restrictive) mempool instead of expansive or private tiers. Constraints respected (no new opcodes, precompiles, frame modes, system contracts, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md).

## 2. Motivation

Today, EIP-8141 has no protocol-level validity window. The only workaround is a VERIFY frame reading `block.timestamp`, which uses an environmental opcode during validation and drops the tx out of restrictive-tier admission. Wallets cannot ship "valid for the next 90 seconds" txs publicly. Moving the bound into the envelope, checked once at tx entry, lets the tx propagate publicly without simulating any frame.

## 3. Priorities and non-goals

Priorities:

1. Protocol-level, not VERIFY-level. Keep the restrictive tier admissible.
2. First-class 8141 primitive, not inherited from ERC-4337's UserOperation payload.
3. Timestamp-based, not block-number-based. Wallet UX is cleaner; post-merge slot timing is deterministic.

Non-goals:

- Block-number bounds.
- Recurring / cron execution.
- On-chain schedulers.
- Reverse-window admission (handled as consensus-invalid).

## 4. Single-line spec delta

Add envelope fields `valid_after: uint64` and `valid_before: uint64` (unix seconds; zero = no bound). Consensus rejects any tx included when `block.timestamp` falls outside `(valid_after, valid_before)`.

## 5. Normative spec

### Envelope

```
[chain_id, nonce, sender, frames, fees..., blob_versioned_hashes,
 valid_after, valid_before]
```

- `valid_after: uint64`, unix seconds. Zero = no lower bound. For `valid_after > 0`, tx invalid unless `block.timestamp > valid_after`.
- `valid_before: uint64`, unix seconds. Zero = no upper bound. For `valid_before > 0`, tx invalid unless `block.timestamp < valid_before`.

Both fields covered by existing `compute_sig_hash` (Class A binding; see [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)). MUST NOT add a sighash rule change.

### Pre-tx consensus check (MUST)

```
if valid_after  != 0 and block.timestamp <= valid_after:  invalid
if valid_before != 0 and block.timestamp >= valid_before: invalid
if valid_after  != 0 and valid_before != 0 and valid_after >= valid_before: invalid
```

Bounds exclusive on both ends. A tx in a block whose timestamp violates either bound is invalid; the block is invalid if it includes such a tx. Reverse windows (both non-zero, `valid_after >= valid_before`) MUST be rejected.

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

Three states are deterministic from the envelope (nodes don't simulate any frame, which is why restrictive-tier admission works): **future-valid** (`block.timestamp <= valid_after`), **ready** (inside window), **expired** (`block.timestamp >= valid_before`).

### Consensus-relevant (MUST)

- **Inclusion validity:** the pre-tx check in §5 is a consensus rule. A tx in a block whose timestamp violates either bound is invalid; the block is invalid if it includes such a tx. Reverse windows are consensus-invalid.

### Node policy (SHOULD)

- **Tiered deferral horizon:** public mempool admits `valid_after - now <= 1 hour`; expansive tier up to 24 hours; direct-to-builder unlimited. Beyond a tier's horizon fails with `validity_window_too_far_future`.
- **Gossip threshold:** future-valid txs held locally until within `GOSSIP_THRESHOLD = 60 seconds` (5 slots) of `valid_after`, then gossiped.
- **Max pending future-valid txs per sender:** e.g., 16.
- **RBF while future-valid:** applies; replacement MUST also satisfy its own validity window (consensus enforces).
- **Expired txs:** dropped on each new head.

## 7. RPC and wallet surface

Four canonical error codes at JSON-RPC `-32010..-32013`:

| Name | Code | Meaning |
|---|---|---|
| `validity_window_too_far_future` | -32010 | `valid_after` beyond tier horizon |
| `validity_window_not_yet_valid` | -32011 | `valid_after` future, node doesn't buffer |
| `validity_window_already_expired` | -32012 | `valid_before <= block.timestamp` |
| `validity_window_reverse` | -32013 | `valid_after >= valid_before` (both non-zero) |

Wallet display (non-normative):

- Local-time equivalents alongside timestamps.
- Relative duration ("valid for 2 minutes").
- Warn on unusually long windows.
- Warn on already-expired or reverse windows before signing.
- For scheduled txs, surface "not valid before <time>" prominently.
- Hardware wallets parse both envelope fields natively.

## 8. Security and DoS analysis

- **Public-mempool buffer size.** Tiered deferral horizon (1 h public, 24 h expansive) bounds how many future-valid txs a node retains, capping memory and bandwidth pressure.
- **Replay against expired signatures.** A signed tx with `valid_before` set is no longer includable past that timestamp, even if the signer never sent a replacement. Replaces ad-hoc deadline parsing in app contracts.
- **MEV / auction contention.** Tight `valid_before` lets wallets express "land in the next n seconds or fail," reducing stale execution risk after market moves.
- **Reverse-window safety.** Reverse windows are consensus-invalid (§5). Nodes drop them before propagation as a node-policy follow-on, removing a class of always-invalid txs from gossip.

## 9. Compatibility and interactions

- **Sighash binding:** resolved by envelope placement (Class A; see [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)).
- **Guarantors:** if a tx expires between admission and inclusion, mempool drops it; guarantor doesn't pay for non-includable txs.
- **Flexible nonces:** orthogonal. A future-valid tx holds its stream position until it lands or expires; doesn't block other streams.
- **Signer binding:** orthogonal. Window enforcement runs before any frame; the verified-signers table is rebuilt per-tx.
- **vs. Tempo:** same shape, same reasoning. Both native designs converge on envelope-level validity.
- **vs. ERC-4337:** 4337's `validUntil`/`validAfter` live in UserOperation payload, enforced by bundlers. Protocol nodes have no view. This proposal moves the primitive down into the protocol.
- **vs. VERIFY-frame workaround:** works on-chain but fails publicly because `block.timestamp` reads drop txs into expansive/private tiers.

## 10. Open questions

None block this proposal. Q1 (deferral horizon) and Q2 (`GOSSIP_THRESHOLD`) are picked as 1 h / 24 h / unlimited and 60 seconds; both are node policy and tunable post-shipping.

## 11. Appendix references

- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A binding (envelope placement).
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.

## 12. EIP-ready delta

1. Add envelope fields `valid_after: uint64`, `valid_before: uint64`; zero = no bound for both.
2. Consensus check at tx entry: strict `>` lower, strict `<` upper. Reverse windows invalid.
3. Mempool: tiered deferral horizon (1 h / 24 h / unlimited), `GOSSIP_THRESHOLD = 60 s`, RBF while future-valid, expired eviction on new head.
4. Four JSON-RPC error codes at `-32010..-32013`.
5. Wallet-display appendix (non-normative).

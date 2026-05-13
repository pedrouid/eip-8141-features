# Auth Scopes for EIP-8141

```
Status:             research draft
Depends on:         EIP-8141 + guarantors
Introduces:         signer, expiry envelope fields;
                    AuthManager (merged); verified-signers table;
                    modified ECRECOVER
Shared appendices:  system-contracts, verified-signers, mempool-tiers,
                    sighash-binding, guarantors, pq-analysis
```

## 1. Status and scope

Aggregated alternative. All three features in one upgrade: Flexible nonces + signer binding + envelope expiry. This doc is the merged spec; sections labelled **Inherited from §X** restate component content, sections labelled **New** cover the cross-feature analysis. Constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md). Identified as the maximum viable bundle in [`docs/priorities.md`](../priorities.md). The consolidated EIP draft [`/eip-8141.md`](../../eip-8141.md) is the PR-shaped execution of this proposal; [`docs/compare.md`](../compare.md) is the delta map against upstream.

## 2. Motivation

Together, the three features give every EIP-8141 account a protocol-level vocabulary across three dimensions of **authorization scoping**: stream (`signer`), time (`expiry`), and subject (PQ accounts via signer binding). Wallets can express "this signed tx is authorized on stream X, until time T, by account A whose PQ pubkey is registered" without leaving consensus. The `expiry` half is what makes intent-style flows (signed-order DEXes, cross-chain bridges, RFQ aggregators, gasless swaps) consensus-enforceable end-to-end: their deadlines stop relying on filler honesty and become an admission rule every node respects.

## 3. Priorities and non-goals

Priorities:

1. Two envelope fields: `signer`, `expiry`. No envelope field for signer binding. No future-valid / `valid_after` field; see [`envelope-expiry.md`](envelope-expiry.md) §3.
2. One system contract: `AuthManager`, holding both keyed nonce streams and registered signers. Immutable.
3. `ECRECOVER` ABI unchanged.
4. Universal coverage on activation day for nonce streams and `expiry`; opt-in PQ signer binding via registration.

Non-goals:

- Pruning / reclamation of nonce-stream slots (v2).
- Future-valid / scheduled activation (offchain by deferring submission).
- Recurring / cron execution. On-chain schedulers.
- Block-builder binding aggregation (defer to PQ stage 2).
- Cross-tx binding. Inline envelope pubkeys. Block-number window bounds.

## 4. Single-line spec delta

Add envelope fields `signer: uint64` (default 0) and `expiry: uint64` (default 0). Deploy immutable `AuthManager` at a reserved address, holding per-account `(signer, schemeId, pubkey)` entries and per-signer 64-bit nonce sequences. Consensus pre-tx checks the deadline, system-calls `AuthManager` for non-zero `signer`, and clears the tx-scoped verified-signers table. PQ VERIFY frames bind `(digest, address)` claims via `AuthManager` pubkey lookup; `ECRECOVER` consults the table first.

## 5. Normative spec

### Envelope

```
[chain_id, signer, nonce, sender, frames, fees..., blob_versioned_hashes,
 expiry]
```

All envelope-native; `compute_sig_hash` covers them. No envelope field for signer binding. MUST NOT add a sighash rule change.

### System contract (Inherited; spec in appendix)

`AuthManager` is specified in [`appendix/system-contracts.md`](../appendix/system-contracts.md). Single reserved address, address + code hash pinned, immutable. Holds keyed nonce streams and signer registrations under one storage layout.

### Pre-tx consensus check (MUST)

```
if tx.expiry != 0 and block.timestamp >= tx.expiry: invalid

// Pre-frame (consensus equality check only; no advance)
if tx.signer == 0:
    require tx.nonce == state[tx.sender].nonce
else:
    require AUTH_MANAGER.checkNonce(tx.sender, tx.signer, tx.nonce)

// (Post-inclusion advance runs once after the expiry rule resolves; see Behavior)

clear tx.verified_signers
```

Bound exclusive. A tx in a block whose timestamp is at or past `tx.expiry` is invalid; the block is invalid if it includes such a tx.

### Stream and window invariants (Inherited; MUST)

- Streams independent per `(sender, signer)`; sequence advances on inclusion regardless of VERIFY outcome (cited from [`appendix/guarantors.md`](../appendix/guarantors.md)).
- Mempool states for time-bounded txs: ready, expired. There is no future-valid state.
- Overflow at `2^64 - 1` is unreachable (last valid sequence is `2^64 - 2`).
- Contract-creation address derivation uses the legacy `nonce` field only.

### Binding semantics (Inherited; spec in appendix)

Verified-signers table lifecycle, population rule, conflict semantics, and modified `ECRECOVER` pseudocode are specified once in [`appendix/verified-signers.md`](../appendix/verified-signers.md). Per-tx cap: `MAX_BOUND_SIGNERS = 8` (MUST NOT exceed).

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **Expiry check at inclusion:** see §5.
- **Block-invalidation (stream side):** stream increment invalidates pending txs at pre-increment sequence on that stream.
- **Cap enforcement (binding side):** `MAX_BOUND_SIGNERS = 8` per tx; see [`appendix/verified-signers.md`](../appendix/verified-signers.md).
- **RBF expiry constraint:** replacement keyed on `(sender, signer, tx.nonce)` MUST also satisfy its own `expiry` (the inclusion check applies to the replacement).
- **Sponsor binding:** sponsor signatures MUST bind `(sender, signer, tx.nonce)`.

### Node policy (SHOULD)

- **Restrictive-tier admission:** expiry check (envelope-only); one slot read on `AuthManager` (`getNonce`) per touched stream; one slot read on `AuthManager` (`getSigner`) per binding frame.
- **Expiry readiness:** deterministic from envelope. Expired txs dropped on each new head.
- **Stream readiness:** `tx.nonce == AUTH_MANAGER.getNonce(sender, signer)`.
- **DoS caps:** `MAX_ACTIVE_SIGNERS_PER_SENDER = 16` (mempool only).

## 7. RPC and wallet surface

```
eth_getTransactionCountBySigner(address, signer, blockTag) → uint64
eth_getRegisteredPubkey(address, blockTag)                 → (uint16, bytes) | null
eth_simulateSignerBinding(tx)                              → list[(digest, address)]
```

Error codes:

| Code | Name |
|---|---|
| -32010..-32011 | Expiry codes (see [`envelope-expiry.md`](envelope-expiry.md) §8) |
| -32014 | `signer_not_registered` |
| -32015 | `too_many_active_signers` |
| -32016..-32018 | Pubkey-side codes (see [`signer-binding.md`](signer-binding.md) §7) |
| -32019 | `signer_binding_cap_exceeded` |

Wallet UX:

- **Expiry:** local-time equivalent alongside the timestamp; relative duration; warn on unusually long expirations and on already-passed `expiry` before signing.
- **Streams:** signer 0 as "Main sequence #n"; known signers labeled; first-use surcharge warned.
- **Signer binding:** one-time pubkey registration onboarding; per-tx surfacing of "recognized via `permit`."

## 8. Security and DoS analysis

Per-feature analyses in components apply. **New** cross-feature considerations:

- **No future-valid stream reservation.** Without `valid_after`, there is no future-valid mempool state; an unexpired tx on stream X with non-zero `signer` is either ready or expired. Mempool buffering for activation timing is gone.
- **RBF across all three dimensions.** Replacement keyed on `(sender, signer, tx.nonce)` MUST also satisfy its own `expiry`; otherwise expired replacements would orphan the original.
- **Binding under expiry.** Binding is rebuilt at execution time, not at admission; `AuthManager` signer state at execution time is what matters. A pubkey rotation before inclusion is honoured.
- **First-use cost stacking.** First-time use of all three features in one tx: expiry check (free) + stream SSTORE-from-zero + pubkey-registration cost (separate tx). Wallets warn once per onboarding step.
- **Pull-out resilience.** Any of the three features can be removed late without invalidating the other two; the nonce and signer halves of `AuthManager` do not cross-reference at the storage layer.

## 9. Compatibility and interactions

- **Guarantors:** orthogonal across all three primitives. Stream-advance invariant survives VERIFY failure under guarantor backing.
- **Sighash binding:** stream key and `expiry` bound by envelope placement (Class A); binding digests sit in elided VERIFY data, integrity from signature-over-pubkey check (Class B). See [`appendix/sighash-binding.md`](../appendix/sighash-binding.md).
- **vs. shipping each individually across upgrades:** same protocol surface, one upgrade's review effort, shared system-contract precedent, shared mempool-tier reasoning.
- **vs. `key-streams.md`:** adds `expiry`. Cheap addition (one envelope field, no state, no contracts), large user-safety upside.
- **vs. ERC-4337:** 4337 has analogues for Flexible nonces and `validUntil` but only for smart accounts via bundlers; no analogue for signer binding.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `AuthManager` nonce-side storage | Best-guess; see [`docs/overview.md`](../overview.md). |

## 11. Appendix references

- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for `AuthManager`.
- [`appendix/verified-signers.md`](../appendix/verified-signers.md) for binding mechanism.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A and Class B.
- [`appendix/guarantors.md`](../appendix/guarantors.md) for stream-advance invariant.
- [`appendix/pq-analysis.md`](../appendix/pq-analysis.md) for scheme sizes.

## 12. EIP-ready delta

1. Envelope: add `signer`, `expiry`.
2. Reinterpret `tx.nonce` as per-stream sequence.
3. Deploy immutable `AuthManager` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
4. Pre-tx rule: `expiry` check (envelope-only); non-zero keys system-call `AuthManager`; clear verified-signers table.
5. PQ VERIFY frames bind `(digest, target)` per [`appendix/verified-signers.md`](../appendix/verified-signers.md).
6. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
7. RPC + error codes as listed (two expiry codes + signer/binding codes).
8. Mempool: per-stream RBF, expired eviction, `MAX_ACTIVE_SIGNERS_PER_SENDER = 16`, `MAX_BOUND_SIGNERS = 8`, block-invalidation rule.
9. Stream advance on inclusion regardless of VERIFY outcome (normative).
10. Reference execution: [`/eip-8141.md`](../../eip-8141.md) is the consolidated EIP draft and [`assets/eip-8141/`](../../assets/eip-8141/) holds the reference contracts (`AuthManager.sol`, `CanonicalPaymaster.sol`).

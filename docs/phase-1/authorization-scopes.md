# Authorization Scopes for EIP-8141

```
Status:             research draft
Phase:              1
Alternative ID:     P1.NSW
Depends on:         EIP-8141 + guarantors
Introduces:         nonce_key, valid_after, valid_before envelope fields;
                    NonceLaneRegistry, PubkeyRegistry; verified-signers table;
                    modified ECRECOVER
Shared appendices:  system-contracts, verified-signers, mempool-tiers,
                    sighash-binding, guarantors, pq-analysis
```

## 1. Status and scope

Phase-1 alternative (aggregated). All three Phase-1 features in one upgrade: 2D nonces (P1.N) + signer binding (P1.S) + validity windows (P1.W). This doc is the merged spec; sections labelled **Inherited from §X** restate component content, sections labelled **New** cover the cross-feature analysis. Constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md). Identified as the maximum viable bundle in [`docs/priorities.md`](../priorities.md).

## 2. Motivation

Together, the three features give every EIP-8141 account a protocol-level vocabulary across three dimensions of **authorization scoping**: stream (`nonce_key`), time (`valid_after` / `valid_before`), and subject (PQ accounts via signer binding). Wallets can express "this signed tx is authorized on lane X, between times T1 and T2, by account A whose PQ pubkey is registered" without leaving consensus.

## 3. Priorities and non-goals

Priorities:

1. Three envelope fields: `nonce_key`, `valid_after`, `valid_before`. No envelope field for signer binding.
2. Two system contracts: `NonceLaneRegistry` and `PubkeyRegistry`. Both immutable.
3. `ECRECOVER` ABI unchanged.
4. Universal coverage on activation day for nonce streams and validity windows; opt-in PQ signer binding via registration.

Non-goals:

- Pruning / reclamation of nonce-lane slots (v2).
- Recurring / cron execution. On-chain schedulers.
- Block-builder binding aggregation (defer to PQ stage 2).
- Cross-tx binding. Inline envelope pubkeys. Block-number window bounds.

## 4. Single-line spec delta

Add envelope fields `nonce_key: uint256` (default 0), `valid_after: uint64` (default 0), `valid_before: uint64` (default 0). Deploy immutable `NonceLaneRegistry` and `PubkeyRegistry` at reserved addresses. Consensus pre-tx checks the validity window, system-calls `NonceLaneRegistry` for non-zero keys, and clears the tx-scoped verified-signers table. PQ VERIFY frames bind `(digest, address)` claims via registry pubkey lookup; `ECRECOVER` consults the table first.

## 5. Normative spec

### Envelope

```
[chain_id, nonce_key, nonce, sender, frames, fees..., blob_versioned_hashes,
 valid_after, valid_before]
```

All envelope-native; `compute_sig_hash` covers them. No envelope field for signer binding. MUST NOT add a sighash rule change.

### System contracts (Inherited; specs in appendix)

`NonceLaneRegistry` and `PubkeyRegistry` are specified once in [`appendix/system-contracts.md`](../appendix/system-contracts.md). Both at upgrade-coordinated reserved addresses, address + code hash pinned, immutable.

### Pre-tx consensus check (MUST)

```
if valid_after  != 0 and block.timestamp <= valid_after:  invalid
if valid_before != 0 and block.timestamp >= valid_before: invalid
if valid_after  != 0 and valid_before != 0 and valid_after >= valid_before: invalid

if tx.nonce_key == 0:
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require NONCE_REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    NONCE_REGISTRY.advance(tx.sender, tx.nonce_key)

clear tx.verified_signers
```

Bounds exclusive on both ends. A tx in a block whose timestamp violates either bound is invalid; the block is invalid if it includes such a tx.

### Stream and window invariants (Inherited; MUST)

- Streams independent per `(sender, nonce_key)`; sequence advances on inclusion regardless of VERIFY outcome (cited from [`appendix/guarantors.md`](../appendix/guarantors.md)).
- Mempool states for windowed txs: future-valid, ready, expired. Future-valid txs hold their stream position.
- Overflow at `2^64 - 1` invalidates further txs on a lane; reverse windows consensus-invalid.
- Contract-creation address derivation uses the legacy `nonce` field only.

### Binding semantics (Inherited; spec in appendix)

Verified-signers table lifecycle, population rule, conflict semantics, and modified `ECRECOVER` pseudocode are specified once in [`appendix/verified-signers.md`](../appendix/verified-signers.md). Per-tx cap: `MAX_BOUND_SIGNERS = 8` (MUST NOT exceed).

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **Validity-window check at inclusion:** see §5; reverse windows consensus-invalid.
- **Block-invalidation (lane side):** lane increment invalidates pending txs at pre-increment sequence on that lane.
- **Cap enforcement (binding side):** `MAX_BOUND_SIGNERS = 8` per tx; see [`appendix/verified-signers.md`](../appendix/verified-signers.md).
- **RBF window constraint:** replacement keyed on `(sender, nonce_key, tx.nonce)` MUST also satisfy its own validity window (the inclusion check applies to the replacement).
- **Sponsor binding:** sponsor signatures MUST bind `(sender, nonce_key, tx.nonce)`.

### Node policy (SHOULD)

- **Restrictive-tier admission:** window check (envelope-only); one slot read on `NonceLaneRegistry` per touched lane; one slot read on `PubkeyRegistry` per binding frame.
- **Window readiness:** deterministic from envelope. Future-valid held locally until within `GOSSIP_THRESHOLD = 60 s`. Expired txs dropped on each new head.
- **Tiered deferral horizon:** public mempool admits `valid_after - now <= 1 hour`; expansive 24 hours; direct-to-builder unlimited.
- **Lane readiness:** `tx.nonce == NONCE_REGISTRY.get(sender, key)`.
- **DoS caps:** `MAX_ACTIVE_STREAMS_PER_SENDER = 16` (mempool only).

## 7. RPC and wallet surface

```
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64
eth_getRegisteredPubkey(address, blockTag)                 → (uint16, bytes) | null
eth_simulateSignerBinding(tx)                              → list[(digest, address)]
```

Error codes:

| Code | Name |
|---|---|
| -32010..-32013 | Validity-window codes (see [`phase-1/validity-windows.md`](validity-windows.md) §7) |
| -32014 | `lane_not_found` |
| -32015 | `too_many_active_streams` |
| -32016..-32018 | Pubkey-side codes (see [`phase-1/signer-binding.md`](signer-binding.md) §7) |
| -32019 | `signer_binding_cap_exceeded` |

Wallet UX:

- **Windows:** local-time equivalents alongside timestamps; relative duration; warn on unusually long, already-expired, or reverse windows.
- **Lanes:** key 0 as "Main sequence #N"; known lanes labeled; first-use surcharge warned.
- **Signer binding:** one-time pubkey registration onboarding; per-tx surfacing of "recognized via `permit`."

## 8. Security and DoS analysis

Per-feature analyses in components apply. **New** cross-feature considerations:

- **Future-valid tx reserving its lane.** A future-valid tx with non-zero `nonce_key` holds its stream slot until expiry. Mempool implementations cap pending future-valid txs per sender to bound buffering (node policy).
- **RBF across all three dimensions.** Replacement keyed on `(sender, nonce_key, tx.nonce)` MUST also satisfy its own validity window; otherwise expired replacements would orphan the original.
- **Binding inside a future-valid tx.** Binding is rebuilt at execution time, not at admission; `PubkeyRegistry` state at execution time is what matters. A pubkey rotation between admission and execution is honoured.
- **First-use cost stacking.** First-time use of all three features in one tx: window check (free) + lane SSTORE-from-zero + pubkey-registration cost (separate tx). Wallets warn once per onboarding step.
- **Pull-out resilience.** Any of the three features can be removed late without invalidating the other two; spec sections do not cross-reference outside the merged consensus pre-tx flow above.

## 9. Compatibility and interactions

- **Guarantors:** orthogonal across all three primitives. Stream-advance invariant survives VERIFY failure under guarantor backing.
- **Sighash binding:** lane key and window bounds bound by envelope placement (Class A); binding digests sit in elided VERIFY data, integrity from signature-over-pubkey check (Class B). See [`appendix/sighash-binding.md`](../appendix/sighash-binding.md).
- **vs. shipping each individually across upgrades:** same protocol surface, one upgrade's review effort, shared system-contract precedent, shared mempool-tier reasoning.
- **vs. `key-lanes.md`:** adds validity windows. Cheap addition (envelope-only, no state, no contracts), large user-safety upside.
- **vs. ERC-4337:** 4337 has analogues for 2D nonces and validity windows but only for smart accounts via bundlers; no analogue for signer binding.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `NonceLaneRegistry` | Best-guess; see [`docs/overview.md`](../overview.md). |

## 11. Appendix references

- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for both registries.
- [`appendix/verified-signers.md`](../appendix/verified-signers.md) for binding mechanism.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A and Class B.
- [`appendix/guarantors.md`](../appendix/guarantors.md) for stream-advance invariant.
- [`appendix/pq-analysis.md`](../appendix/pq-analysis.md) for scheme sizes.

## 12. Spec delta summary

1. Envelope: add `nonce_key`, `valid_after`, `valid_before`.
2. Reinterpret `tx.nonce` as per-stream sequence.
3. Deploy immutable `NonceLaneRegistry` and `PubkeyRegistry` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
4. Pre-tx rule: window check (envelope-only); non-zero keys system-call nonce registry; clear verified-signers table.
5. PQ VERIFY frames bind `(digest, target)` per [`appendix/verified-signers.md`](../appendix/verified-signers.md).
6. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
7. RPC + ten error codes as listed.
8. Mempool: tiered window deferral, per-lane RBF, `MAX_ACTIVE_STREAMS_PER_SENDER = 16`, `MAX_BOUND_SIGNERS = 8`, block-invalidation rule.
9. Stream advance on inclusion regardless of VERIFY outcome (normative).

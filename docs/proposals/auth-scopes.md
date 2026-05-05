# Auth Scopes for EIP-8141

```
Status:             research draft
Depends on:         EIP-8141 + guarantors
Introduces:         signer, valid_after, valid_before envelope fields;
                    AuthManager (merged); verified-signers table;
                    modified ECRECOVER
Shared appendices:  system-contracts, verified-signers, mempool-tiers,
                    sighash-binding, guarantors, pq-analysis
```

## 1. Status and scope

Aggregated alternative. All three features in one upgrade: Flexible nonces + signer binding + validity windows. This doc is the merged spec; sections labelled **Inherited from §X** restate component content, sections labelled **New** cover the cross-feature analysis. Constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md). Identified as the maximum viable bundle in [`docs/priorities.md`](../priorities.md). The consolidated EIP draft [`/eip-8141.md`](../../eip-8141.md) is the PR-shaped execution of this proposal; [`docs/compare.md`](../compare.md) is the delta map against upstream.

## 2. Motivation

Together, the three features give every EIP-8141 account a protocol-level vocabulary across three dimensions of **authorization scoping**: stream (`signer`), time (`valid_after` / `valid_before`), and subject (PQ accounts via signer binding). Wallets can express "this signed tx is authorized on stream X, between times T1 and T2, by account A whose PQ pubkey is registered" without leaving consensus.

## 3. Priorities and non-goals

Priorities:

1. Three envelope fields: `signer`, `valid_after`, `valid_before`. No envelope field for signer binding.
2. One system contract: `AuthManager`, holding both keyed nonce streams and registered signers. Immutable.
3. `ECRECOVER` ABI unchanged.
4. Universal coverage on activation day for nonce streams and validity windows; opt-in PQ signer binding via registration.

Non-goals:

- Pruning / reclamation of nonce-stream slots (v2).
- Recurring / cron execution. On-chain schedulers.
- Block-builder binding aggregation (defer to PQ stage 2).
- Cross-tx binding. Inline envelope pubkeys. Block-number window bounds.

## 4. Single-line spec delta

Add envelope fields `signer: uint64` (default 0), `valid_after: uint64` (default 0), `valid_before: uint64` (default 0). Deploy immutable `AuthManager` at a reserved address, holding per-account `(signer, schemeId, pubkey)` entries and per-signer 64-bit nonce sequences. Consensus pre-tx checks the validity window, system-calls `AuthManager` for non-zero `signer`, and clears the tx-scoped verified-signers table. PQ VERIFY frames bind `(digest, address)` claims via `AuthManager` pubkey lookup; `ECRECOVER` consults the table first.

## 5. Normative spec

### Envelope

```
[chain_id, signer, nonce, sender, frames, fees..., blob_versioned_hashes,
 valid_after, valid_before]
```

All envelope-native; `compute_sig_hash` covers them. No envelope field for signer binding. MUST NOT add a sighash rule change.

### System contract (Inherited; spec in appendix)

`AuthManager` is specified in [`appendix/system-contracts.md`](../appendix/system-contracts.md). Single reserved address, address + code hash pinned, immutable. Holds keyed nonce streams and signer registrations under one storage layout.

### Pre-tx consensus check (MUST)

```
if valid_after  != 0 and block.timestamp <= valid_after:  invalid
if valid_before != 0 and block.timestamp >= valid_before: invalid
if valid_after  != 0 and valid_before != 0 and valid_after >= valid_before: invalid

// Pre-frame (consensus equality check only; no advance)
if tx.signer == 0:
    require tx.nonce == state[tx.sender].nonce
else:
    require AUTH_MANAGER.checkNonce(tx.sender, tx.signer, tx.nonce)

// (Post-inclusion advance runs once after the validity rule resolves; see Behavior)

clear tx.verified_signers
```

Bounds exclusive on both ends. A tx in a block whose timestamp violates either bound is invalid; the block is invalid if it includes such a tx.

### Stream and window invariants (Inherited; MUST)

- Streams independent per `(sender, signer)`; sequence advances on inclusion regardless of VERIFY outcome (cited from [`appendix/guarantors.md`](../appendix/guarantors.md)).
- Mempool states for windowed txs: future-valid, ready, expired. Future-valid txs hold their stream position.
- Overflow at `2^64 - 1` is unreachable (last valid sequence is `2^64 - 2`); reverse windows consensus-invalid.
- Contract-creation address derivation uses the legacy `nonce` field only.

### Binding semantics (Inherited; spec in appendix)

Verified-signers table lifecycle, population rule, conflict semantics, and modified `ECRECOVER` pseudocode are specified once in [`appendix/verified-signers.md`](../appendix/verified-signers.md). Per-tx cap: `MAX_BOUND_SIGNERS = 8` (MUST NOT exceed).

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **Validity-window check at inclusion:** see §5; reverse windows consensus-invalid.
- **Block-invalidation (stream side):** stream increment invalidates pending txs at pre-increment sequence on that stream.
- **Cap enforcement (binding side):** `MAX_BOUND_SIGNERS = 8` per tx; see [`appendix/verified-signers.md`](../appendix/verified-signers.md).
- **RBF window constraint:** replacement keyed on `(sender, signer, tx.nonce)` MUST also satisfy its own validity window (the inclusion check applies to the replacement).
- **Sponsor binding:** sponsor signatures MUST bind `(sender, signer, tx.nonce)`.

### Node policy (SHOULD)

- **Restrictive-tier admission:** window check (envelope-only); one slot read on `AuthManager` (`getNonce`) per touched stream; one slot read on `AuthManager` (`getSigner`) per binding frame.
- **Window readiness:** deterministic from envelope. Future-valid held locally until within `GOSSIP_THRESHOLD = 60 s`. Expired txs dropped on each new head.
- **Tiered deferral horizon:** public mempool admits `valid_after - now <= 1 hour`; expansive 24 hours; direct-to-builder unlimited.
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
| -32010..-32013 | Validity-window codes (see [`validity-windows.md`](validity-windows.md) §7) |
| -32014 | `signer_not_registered` |
| -32015 | `too_many_active_signers` |
| -32016..-32018 | Pubkey-side codes (see [`signer-binding.md`](signer-binding.md) §7) |
| -32019 | `signer_binding_cap_exceeded` |

Wallet UX:

- **Windows:** local-time equivalents alongside timestamps; relative duration; warn on unusually long, already-expired, or reverse windows.
- **Streams:** signer 0 as "Main sequence #n"; known signers labeled; first-use surcharge warned.
- **Signer binding:** one-time pubkey registration onboarding; per-tx surfacing of "recognized via `permit`."

## 8. Security and DoS analysis

Per-feature analyses in components apply. **New** cross-feature considerations:

- **Future-valid tx reserving its stream.** A future-valid tx with non-zero `signer` holds its stream slot until expiry. Mempool implementations cap pending future-valid txs per sender to bound buffering (node policy).
- **RBF across all three dimensions.** Replacement keyed on `(sender, signer, tx.nonce)` MUST also satisfy its own validity window; otherwise expired replacements would orphan the original.
- **Binding inside a future-valid tx.** Binding is rebuilt at execution time, not at admission; `AuthManager` signer state at execution time is what matters. A pubkey rotation between admission and execution is honoured.
- **First-use cost stacking.** First-time use of all three features in one tx: window check (free) + stream SSTORE-from-zero + pubkey-registration cost (separate tx). Wallets warn once per onboarding step.
- **Pull-out resilience.** Any of the three features can be removed late without invalidating the other two; the nonce and signer halves of `AuthManager` do not cross-reference at the storage layer.

## 9. Compatibility and interactions

- **Guarantors:** orthogonal across all three primitives. Stream-advance invariant survives VERIFY failure under guarantor backing.
- **Sighash binding:** stream key and window bounds bound by envelope placement (Class A); binding digests sit in elided VERIFY data, integrity from signature-over-pubkey check (Class B). See [`appendix/sighash-binding.md`](../appendix/sighash-binding.md).
- **vs. shipping each individually across upgrades:** same protocol surface, one upgrade's review effort, shared system-contract precedent, shared mempool-tier reasoning.
- **vs. `key-streams.md`:** adds validity windows. Cheap addition (envelope-only, no state, no contracts), large user-safety upside.
- **vs. ERC-4337:** 4337 has analogues for Flexible nonces and validity windows but only for smart accounts via bundlers; no analogue for signer binding.

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

1. Envelope: add `signer`, `valid_after`, `valid_before`.
2. Reinterpret `tx.nonce` as per-stream sequence.
3. Deploy immutable `AuthManager` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
4. Pre-tx rule: window check (envelope-only); non-zero keys system-call `AuthManager`; clear verified-signers table.
5. PQ VERIFY frames bind `(digest, target)` per [`appendix/verified-signers.md`](../appendix/verified-signers.md).
6. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
7. RPC + ten error codes as listed.
8. Mempool: tiered window deferral, per-stream RBF, `MAX_ACTIVE_SIGNERS_PER_SENDER = 16`, `MAX_BOUND_SIGNERS = 8`, block-invalidation rule.
9. Stream advance on inclusion regardless of VERIFY outcome (normative).
10. Reference execution: [`/eip-8141.md`](../../eip-8141.md) is the consolidated EIP draft and [`assets/eip-8141/`](../../assets/eip-8141/) holds the reference contracts (`AuthManager.sol`, `CanonicalPaymaster.sol`).

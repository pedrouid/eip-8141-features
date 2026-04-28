# 2D Nonces for EIP-8141

```
Status:             research draft
Phase:              1
Alternative ID:     P1.N
Depends on:         EIP-8141 + guarantors
Introduces:         nonce_key envelope field, NonceLaneRegistry
Shared appendices:  system-contracts, mempool-tiers, sighash-binding, guarantors
```

## 1. Status and scope

Phase-1 alternative (individual). Adds protocol-native parallel nonce streams per account. Consensus surface is one envelope field plus one immutable system contract; constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md).

## 2. Motivation

Today, a single stuck low-fee tx blocks every later tx from the same EOA. The workaround is to deploy a smart account or maintain multiple addresses. 2D nonces let one account run independent sequences in parallel, so a stuck app-key tx does not block a recovery tx, a payroll tx does not block a swap, and so on.

## 3. Priorities and non-goals

Priorities:

1. One envelope field. Consensus MUST bind the stream key; no account-side signature can cover it.
2. No account-encoding changes. Lane state lives in a system contract.
3. Preserve the legacy `nonce` slot. The existing account `nonce` field holds the sequence on key 0.
4. Universal EOA coverage on activation day.

Non-goals:

- Pruning or reclamation of lane slots (v2).
- Custom per-signer scoping logic at consensus (left to default-code design via tx-context).

## 4. Single-line spec delta

Add envelope field `nonce_key: uint256` (default 0). Deploy `NonceLaneRegistry` at a reserved address. For `nonce_key > 0`, consensus pre-tx system-calls the registry to check-and-advance the sequence. For `nonce_key == 0`, the legacy path is byte-for-byte identical to today.

## 5. Normative spec

### Envelope

```
[chain_id, nonce_key, nonce, sender, frames, fees..., blob_versioned_hashes]
```

- `nonce_key: uint256`, stream selector. Default 0. Positioned immediately before `nonce` so `nonce` keeps its RLP index.
- `nonce: uint64`, position unchanged; reinterpreted as the sequence within the stream.

Both envelope-native; `compute_sig_hash` covers them. **MUST NOT** add a sighash rule change.

### Registry

`NonceLaneRegistry` (interface, deployment, immutability, code-hash pinning, first-use cost, why account-RLP was rejected) is specified in [`appendix/system-contracts.md`](../appendix/system-contracts.md).

### Pre-tx consensus check (MUST)

```
if tx.nonce_key == 0:
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    REGISTRY.advance(tx.sender, tx.nonce_key)
```

### Stream invariants (MUST)

- **Independence.** A gap on key A MUST NOT block key B.
- **Stream advance on inclusion.** The sequence on a stream MUST advance on successful inclusion regardless of any VERIFY-frame outcome. If sender VERIFY fails on-chain but a guarantor pays, the sequence still advances. Cited from [`appendix/guarantors.md`](../appendix/guarantors.md).
- **Overflow.** `tx.nonce = 2^64 - 1` is the last valid sequence on a lane; further txs on that lane MUST be rejected. Senders migrate to a new `nonce_key`. _Rationale:_ exhaustion is unreachable in practice (~585 billion years at 1 tx/sec).
- **Contract-creation address.** Derivation MUST use the legacy `nonce` field (`nonces[0]`) only.

### Sponsor binding (MUST)

A sponsor signature over a tx MUST bind `(sender, nonce_key, tx.nonce)`. _Rationale:_ a sponsor agreeing to a tx on key 0 must not be replayable as a tx on a different key.

### Account-code visibility

`tx.nonce_key` SHALL be exposed on the default-code tx-context surface (same mechanism as `chain_id`, `sender`). Smart-contract accounts with custom VERIFY read the same context. Enables key-range scoping, per-signer scoping, registered-keys-only, and stream-labeling conventions in a future ERC.

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md). Restrictive-tier admissible: one storage slot read on `NonceLaneRegistry` per touched lane.

### Consensus-relevant (MUST)

- **Block-invalidation:** when a block increments any `(sender, nonce_key)` lane, pending txs at the pre-increment sequence on that lane MUST be invalidated by re-validating against the new lane state. (Block-validity follow-on of the consensus pre-tx check.)
- **Sponsor binding:** sponsor signatures MUST bind `(sender, nonce_key, tx.nonce)` (also stated in §5).

### Node policy (SHOULD)

- **Readiness:** `tx.nonce == REGISTRY.get(sender, key)` (or legacy for key 0).
- **RBF:** matches `(sender, nonce_key, tx.nonce)`.
- **DoS caps:** key 0 always accepted; non-zero keys up to `MAX_ACTIVE_STREAMS_PER_SENDER = 16` concurrent pending streams in public mempool. Consensus-level protection is SSTORE-from-zero cost.

## 7. RPC and wallet surface

```
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64
```

Do not overload `eth_getTransactionCount`; its second parameter is already a block tag. Additional provider surface: pending-count-per-key, tx-lookup by `(sender, nonce_key, nonce)`, replacement status per key, `eth_estimateGas` surfacing SSTORE-from-zero first-use surcharge.

Error codes: `lane_not_found`, `too_many_active_streams`.

Wallet UX: key 0 shown as "Main sequence #N"; known lanes labeled by wallet convention; unknown lanes flagged; first-use of a non-zero lane warned as extra gas. Common key-selection strategies: app / session keys, admin key (reserved high-bit for recovery), ephemeral keys.

## 8. Security and DoS analysis

- **State growth.** Each non-zero lane is one slot in `NonceLaneRegistry`. Adversarial flood: 30 Mgas / 20k SSTORE-from-zero ≈ 1500 lanes/block, ~1 GB/day uncapped. Mempool cap and SSTORE pricing keep realistic growth at ~2 GB/year. Best-guess pending cross-client benchmarks; see open questions.
- **Replay across keys.** Sponsor binding (above) closes cross-key replay. Without it a sponsor signature on `(sender, key=0, nonce=N)` would be replayable as `(sender, key=1, nonce=N)`.
- **Block-invalidation churn.** Per-lane invalidation can cascade if many lanes increment in one block; mempool implementations should recompute readiness per-lane independently (node policy).
- **Lane squatting.** First-use cost (SSTORE-from-zero, 20 000 gas) economically bounds adversarial allocation. No reclamation in v1.

## 9. Compatibility and interactions

- **Guarantors:** reinforces stream-advance-on-inclusion invariant.
- **Validity windows:** orthogonal. A future-valid tx holds its stream position until it lands or expires; doesn't block other streams.
- **Signer binding:** orthogonal. Binding scope is tx-local; nonce-stream selection is tx-level.
- **Sighash binding:** resolved by envelope placement (Class A; see [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)).
- **vs. ERC-4337:** 4337 packs key+seq into one `uint256` because it lives above the protocol. 8141 uses two independent envelope fields. Universal EOA coverage, no bundler.
- **vs. Tempo:** both clean-slate; both converge on `(uint256, uint64)`. 8141 preserves programmable VERIFY, PQ roadmap, frame composability.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `NonceLaneRegistry` | Best-guess pending cross-client benchmarks. See [`docs/overview.md`](../overview.md) open uncertainties. |

## 11. Appendix references

- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for `NonceLaneRegistry` interface, deployment, code-hash pinning, first-use cost, account-RLP rejection.
- [`appendix/guarantors.md`](../appendix/guarantors.md) for the stream-advance-on-inclusion invariant citation.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A binding (envelope placement).

## 12. Spec delta summary

1. Add envelope field `nonce_key: uint256` before the existing `nonce`.
2. Reinterpret `tx.nonce: uint64` as the sequence within the stream.
3. Deploy immutable `NonceLaneRegistry` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
4. Consensus pre-tx rule: non-zero keys system-call `REGISTRY.check` + `REGISTRY.advance`; key 0 legacy path.
5. Stream advances on inclusion regardless of VERIFY outcome (normative).
6. First-use cost: SSTORE-from-zero inside registry.
7. Expose `tx.nonce_key` on default-code tx-context surface.
8. Sponsor signatures MUST bind `(sender, nonce_key, tx.nonce)`.
9. RPC: `eth_getTransactionCountByKey`.
10. Mempool: `MAX_ACTIVE_STREAMS_PER_SENDER = 16`, per-lane RBF, block-invalidation rule.

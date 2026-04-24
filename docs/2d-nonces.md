# 2D Nonces for EIP-8141

_Scratch doc, not indexed on the site._

Gives every EIP-8141 account protocol-native parallel nonce streams via one envelope field and a system contract (EIP-4788 / EIP-2935 pattern). No opcodes, precompiles, frame-model changes, or account-encoding changes.

## Priorities

1. One envelope field. Consensus must bind the stream key; no account-side signature can cover it.
2. No account-encoding changes. Lane state in a system contract, not the account RLP.
3. No new opcodes, precompiles, or frame modes.
4. Preserve the legacy nonce slot. The existing account `nonce` field holds `nonces[0]`.
5. Preserve the envelope `nonce` field as the sequence within a stream.
6. First-class 8141 primitive. Converges with Tempo on `(uint256, uint64)`; no 4337 contract-era inheritance.
7. Universal EOA coverage on activation day.

## 1. Single-line spec delta

> Add envelope field `nonce_key: uint256` (default 0). Deploy `NonceLaneRegistry` at a reserved address, immutable, pinned by address + code hash. For `nonce_key > 0`, consensus pre-tx system-calls the registry to check-and-advance the sequence. For `nonce_key == 0`, the legacy path is byte-for-byte identical to today.

## 2. Envelope

```
[chain_id, nonce_key, nonce, sender, frames, fees...,
 blob_versioned_hashes]
```

- `nonce_key: uint256` — stream selector. Default 0. Positioned immediately before `nonce` so `nonce` keeps its RLP index.
- `nonce: uint64` — unchanged in position; reinterpreted as the sequence number within the stream.

Both envelope-native; `compute_sig_hash` covers them. No sighash rule change.

## 3. NonceLaneRegistry

Deployed at a fork-coordinated reserved address. Immutable. Upgrades ship as new reserved addresses at future forks; existing lane state stays on the old address.

```solidity
contract NonceLaneRegistry {
    mapping(address => mapping(uint256 => uint64)) private lanes;

    function check(address sender, uint256 key, uint64 seq) external view returns (bool);
    function advance(address sender, uint256 key) external;  // SYSTEM_ADDRESS only
    function get(address sender, uint256 key) external view returns (uint64);
}
```

Spec pins: reserved address, expected code hash, fork-activation deployment, SYSTEM_ADDRESS guard on `advance`.

## 4. Consensus pre-tx flow

```
if tx.nonce_key == 0:
    // legacy path, byte-for-byte identical to today
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    REGISTRY.advance(tx.sender, tx.nonce_key)
```

## 5. Stream semantics

- **Independent streams.** A gap on key A never blocks key B.
- **Normative invariant**: the sequence on a stream advances on successful inclusion regardless of any VERIFY frame's outcome. If sender VERIFY fails on-chain but a guarantor pays, the sequence still advances. Referenced by `guarantors.md` and `validity-windows.md`.
- **Overflow**: `tx.nonce = 2^64 - 1` is the last valid sequence on a lane; subsequent txs on that lane are consensus-invalid. Sender migrates to a new `nonce_key`.
- **Contract creation address derivation**: uses the legacy `nonce` field (`nonces[0]`) only.

## 6. State model

Lane state lives in `state[REGISTRY].storage`, keyed by standard nested-mapping layout. Unchanged: account RLP, outer state-trie shape, EIP-161 semantics, archive decoding. Witnesses are standard storage proofs against the registry's `storageRoot`. Verkle / state-tree transition inherits from contract storage; no bespoke work.

## 7. First-use cost

First allocation of a non-zero lane is SSTORE-from-zero inside the registry (20 000 gas with EIP-2929 refinements). No separate `LANE_ALLOCATION_COST` constant — existing SSTORE cost schedule prices lane allocation. Pruning / reclamation is v2.

## 8. Account-code visibility

`tx.nonce_key` exposed on the default-code tx-context surface (same mechanism as `chain_id`, `sender`). No new opcode. Smart-contract accounts with custom VERIFY read the same context. Enables: key-range scoping, per-signer binding, registered-keys-only, stream-labeling conventions (future ERC).

## 9. Mempool rules

- **Readiness**: `tx.nonce == REGISTRY.get(sender, key)` (or legacy for key 0). Streams independent.
- **RBF**: matches `(sender, nonce_key, tx.nonce)`.
- **DoS caps (node policy)**: key 0 always accepted; non-zero keys up to `MAX_ACTIVE_STREAMS_PER_SENDER = 16` concurrent pending streams in public mempool. Consensus-level protection is SSTORE-from-zero cost.
- **Sponsor binding**: signatures MUST bind `(sender, nonce_key, tx.nonce)`.
- **Restrictive-tier admission**: one storage slot read from the registry; no shared-state reads, no environmental opcodes.
- **Block-invalidation**: when a block increments any `(sender, nonce_key)` lane, pending txs at the pre-increment sequence on that lane are invalidated.

## 10. VOPS profile

One storage slot read per touched `(sender, nonce_key)`. Witnesses: standard proofs against the registry's `storageRoot`. State-growth budget (pending benchmarks): ~2 GB/year legitimate, ~1 GB/day adversarial cap before SSTORE cost + mempool caps saturate.

## 11. RPC

New method (do not overload `eth_getTransactionCount`; second parameter is already a block tag):

```
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64
```

Additional provider surface: pending-count-per-key, tx-lookup by `(sender, nonce_key, nonce)`, replacement status per key, `eth_estimateGas` surfacing SSTORE-from-zero first-use surcharge, simulation including mempool pending state. Error codes: `lane_not_found`, `too_many_active_streams`.

## 12. Wallet UX

Key-selection strategies: key 0 (default), app / session keys, admin key (reserved high-bit for recovery), ephemeral keys. Hardware-wallet display: key 0 shown as "Main sequence #N"; known lanes labeled; unknown lanes flagged; first-use warned as extra gas.

## 13. Interactions

- Sighash binding: resolved by envelope placement.
- Execution authority: orthogonal. Operates on `tx.sender`'s streams.
- Guarantors: reinforces stream-advance invariant.
- Validity windows: orthogonal. Future-valid tx holds its stream position until lands or expires.

## 14. Comparison

- vs. ERC-4337: 4337 packs key+seq into one `uint256` because it lives above the protocol. 8141 uses two independent envelope fields. Universal EOA coverage; no bundler. No 4337 inheritance.
- vs. Tempo: both clean-slate; both converge on `(uint256, uint64)`. 8141 preserves programmable VERIFY, PQ roadmap, frame composability.

## 15. Spec delta summary

1. Add envelope field `nonce_key: uint256` before the existing `nonce`.
2. Reinterpret `tx.nonce: uint64` as the sequence within the stream.
3. Deploy immutable `NonceLaneRegistry` at a reserved address; pin address + expected code hash.
4. Consensus pre-tx rule: non-zero keys system-call `REGISTRY.check` + `REGISTRY.advance`; key 0 legacy path.
5. Stream advances on inclusion regardless of VERIFY outcome (normative).
6. First-use cost: SSTORE-from-zero inside registry.
7. Expose `tx.nonce_key` on default-code tx-context surface.
8. Sponsor signatures bind `(sender, nonce_key, tx.nonce)`.
9. RPC: `eth_getTransactionCountByKey`.
10. Mempool: `MAX_ACTIVE_STREAMS_PER_SENDER = 16`, per-lane RBF, block-invalidation rule.

**One envelope field. One system contract. Zero opcodes, precompiles, frame modes, account-encoding changes, sighash changes.** Every EOA gets native parallel streams on activation day; restrictive mempool admits them cleanly; SSTORE cost bounds lane allocation.

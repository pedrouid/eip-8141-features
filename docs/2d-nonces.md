# 2D Nonces for EIP-8141

_Author: Claude. Scratch doc, not indexed on the site._

This proposal gives every EIP-8141 account protocol-native parallel nonce streams via one envelope field and a consensus-coordinated system contract, making 2D nonces a restrictive-tier-viable primitive without opcodes, precompiles, frame-model changes, or account-encoding changes.

It is the second rewrite, replacing the earlier "APPROVE-frame prefix" design (which was wrong — there is no APPROVE frame, and VERIFY calldata is elided from `compute_sig_hash`) and the subsequent `lanesRoot` design (which was too invasive — changing the account RLP encoding is a consensus paradigm shift that touches every parser, every state-root computation, EIP-161 semantics, archive-node decoding, and historical queries). The current design uses the EIP-4788 (beacon roots) and EIP-2935 (historical block hashes) system-contract pattern.

---

## Priorities

1. **One envelope field.** A primitive consensus needs to bind (no account-side signature can cover it) lives in the envelope.
2. **No account-encoding changes.** Lane state lives in a system contract, not in the account RLP.
3. **No new opcodes. No new precompiles. No new frame modes.**
4. **Preserve the legacy nonce slot.** The existing account `nonce` field continues to hold `nonces[0]`, byte-for-byte.
5. **Preserve the existing envelope `nonce` field's meaning** as the sequence within a stream.
6. **First-class EIP-8141 primitive.** Converges with Tempo on `(uint256, uint64)` by design; does not inherit from ERC-4337's contract-era packed-slot layout.
7. **Universal EOA coverage on activation day.** No opt-in, no ERC, no account deployment.

---

## 1. Single-line spec delta

> Add envelope field `nonce_key: uint256` (default 0). Deploy `NonceLaneRegistry` system contract at a reserved address, immutable, pinned by address + code hash at fork activation. For `nonce_key > 0`, consensus pre-tx system-calls the registry to check-and-advance the sequence. For `nonce_key == 0`, the legacy path is byte-for-byte identical to today.

---

## 2. Envelope changes

Add `nonce_key: uint256` immediately before the existing `nonce` field so that `nonce` keeps its RLP index:

```
[chain_id, nonce_key, nonce, sender, frames, max_priority_fee_per_gas,
 max_fee_per_gas, max_fee_per_blob_gas, blob_versioned_hashes]
```

- `nonce_key: uint256` — stream selector. Default 0.
- `nonce: uint64` — unchanged in position; reinterpreted as the sequence number within the stream selected by `nonce_key`.

Both are envelope fields, so `compute_sig_hash` already covers them. No sighash rule change.

---

## 3. NonceLaneRegistry — system contract

Deployed at a fork-coordinated reserved address (pattern: EIP-4788 beacon roots at `0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02`, EIP-2935 block hashes at `0x0000F90827F1C53a10cb7A02335B175320002935`). Immutable. Upgrades ship as new reserved addresses at future forks; existing lane state stays on the old address.

```solidity
contract NonceLaneRegistry {
    mapping(address => mapping(uint256 => uint64)) private lanes;

    function check(address sender, uint256 key, uint64 seq) external view returns (bool);
    function advance(address sender, uint256 key) external;  // SYSTEM_ADDRESS only
    function get(address sender, uint256 key) external view returns (uint64);
}
```

Spec pins: reserved address, expected code hash (verified by consensus before call), deployment at fork activation, SYSTEM_ADDRESS guard on `advance`.

---

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

The system-call pattern mirrors EIP-4788's pre-block call to the beacon-root contract: consensus invokes specific contract functions as part of transaction admission, bypassing the normal gas pricing of that call (cost accounted at the consensus layer as first-use surcharge per §7).

---

## 5. Stream semantics

- **Independent streams.** A gap on key `A` never blocks key `B`.
- **Normative invariant**: the sequence on a stream advances on successful inclusion **regardless of any VERIFY frame's outcome**. If sender VERIFY fails on-chain but a guarantor pays (per `guarantors.md`), the sequence on `nonce_key` still advances; the sender simply retries on the next sequence. This keeps stream semantics monotone and decouples replay protection from validation outcome. This invariant is referenced by `guarantors.md` and `validity-windows.md`.
- **Sequence overflow.** `tx.nonce = 2^64 - 1` is the last valid sequence on a lane; subsequent txs on that lane are consensus-invalid. Sender migrates to a new `nonce_key`.
- **Contract creation address derivation.** Uses the legacy `nonce` field (`nonces[0]`) only; non-zero lanes do not participate.

---

## 6. State model

Lane state lives inside `state[REGISTRY].storage`, keyed by Solidity's standard nested-mapping layout (`keccak256(abi.encode(nonce_key, keccak256(abi.encode(sender, SLOT))))`).

What does **not** change:

- Account RLP encoding (4-tuple stays 4-tuple).
- Outer state-trie shape.
- EIP-161 empty-account semantics.
- Witness format — storage witnesses into the registry's `storageRoot` already exist.
- Snap sync / state healing — the registry syncs like any other contract.
- Archive-node decoding.

State-tree transition (Verkle, etc.): inherits from contract-storage migration; no bespoke work.

---

## 7. First-use cost

First allocation of a non-zero lane is an SSTORE-from-zero inside the registry (20 000 gas with EIP-2929 warm/cold refinements applied normally). **No separate `LANE_ALLOCATION_COST` constant** — the existing SSTORE cost schedule prices lane allocation correctly because lane state is ordinary contract storage.

Pruning / reclamation of abandoned lanes is out of scope for v1; deferred to a separate EIP.

---

## 8. Account-code visibility

`tx.nonce_key` is exposed on the default-code tx-context surface (same mechanism used to expose `chain_id`, `sender`, and friends). No new opcode is required; VERIFY frames already receive tx-context metadata through the existing default-code interface, and the spec adds `tx.nonce_key` to that set.

Smart-contract accounts with custom VERIFY code read the same context. This preserves account-code flexibility:

- **Key-range scoping.** Session-key signatures valid only on `nonce_key ∈ [lo, hi]`.
- **Per-signer binding.** Multi-sig signers mapped to disjoint key ranges.
- **Registered-keys-only.** Custom accounts require a key to appear in a storage allowlist.
- **Stream labeling conventions** via a future ERC (derive `nonce_key` from session-ID hash, app domain, intent type).

The stream key being in the envelope does not hide it from account code; it only hides it from arbitrary EVM code that isn't given the tx-context surface.

---

## 9. Mempool and propagation rules

### 9.1 Readiness
Ready when `tx.nonce == state[tx.sender].nonces[tx.nonce_key]` (formally: `REGISTRY.get(sender, key)` for non-zero keys; `state[sender].nonce` for key 0). Streams are independent.

### 9.2 Replace-by-fee
RBF matches on `(sender, nonce_key, tx.nonce)`. A bump on `(sender, 5, 12)` cannot evict `(sender, 0, 12)`.

### 9.3 DoS caps (node policy, not consensus)
- `nonce_key == 0`: always accepted.
- Non-zero keys: up to `MAX_ACTIVE_STREAMS_PER_SENDER = 16` concurrent pending streams in the public mempool.
- Private mempools and builder pools may lift this. Consensus-level protection against uncapped allocation is the SSTORE-from-zero cost in the registry.

### 9.4 Sponsor binding
Sponsor signatures MUST bind `(sender, nonce_key, tx.nonce)`. Binding only `(sender, tx.nonce)` would let a sponsor's gas credit be replayed across lanes.

### 9.5 Validation-tier admission
Restrictive-tier compatible. The consensus pre-tx check reads one storage slot from the registry (`state[REGISTRY].storage[slot_for(sender, nonce_key)]`); no shared-state reads, no environmental opcodes.

### 9.6 Block-invalidation
When a block increments any `(sender, nonce_key)` lane, pending txs at the pre-increment sequence on that lane are invalidated.

---

## 10. VOPS profile

- Lane-state validation reads one storage slot in the registry per `(sender, nonce_key)` touched.
- VOPS slice for a non-zero-lane tx extends by exactly one storage slot in the registry; same shape as any other contract-storage witness.
- Witnesses: standard Merkle/verkle storage proof against the registry's `storageRoot`. No new proof type.
- State-growth budget (pending cross-client benchmarks): ~2 GB/year legitimate, ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate attackers.
- A VOPS attester can validate a non-zero-lane tx by proving the registry's slot matches `tx.nonce - 1`; no full-state lookup needed.

---

## 11. RPC

New method (do not overload `eth_getTransactionCount`; the second parameter is already a block tag in wide library use):

```
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64
```

- `nonce_key == 0` returns the sender's legacy account nonce.
- `nonce_key > 0` returns `REGISTRY.get(address, nonce_key)` at `blockTag`.
- Pending-state variants follow existing conventions.

Additional provider surface:

- Pending-count-per-key variant (tx-tracking).
- Tx-lookup by `(sender, nonce_key, nonce)`.
- Replacement status per key.
- `eth_estimateGas` surfaces the SSTORE-from-zero surcharge for first-use lane allocation.
- Simulation includes mempool pending state on the relevant key.

Standard error codes: `lane_not_found`, `too_many_active_streams`.

---

## 12. Wallet UX

Wallets pick a key-selection strategy:

- **Key 0** — ordinary sequential transactions; default for every wallet that never opts in.
- **App / session keys** — one stream per connected dapp or session.
- **Admin key** — a reserved high-bit key for recovery and permission changes.
- **Ephemeral keys** — random non-zero keys for one-off flows where ordering doesn't matter.

Hardware-wallet display (recommended):

- Key 0: "Main sequence #N".
- Known wallet-created lanes: wallet label, dapp, sequence.
- Unknown lanes: explicit warning.
- First-use non-zero lanes: "Opens a new activity lane (costs additional gas)."

The protocol enforces ordering within each stream; account code can constrain which keys are acceptable; wallets surface human-readable labels.

---

## 13. Interaction with other primitives

- **Sighash binding (`sighash-binding.md`)**: resolved by envelope placement. `nonce_key` is covered by the existing sighash.
- **Execution authority (`execution-authority.md`)**: orthogonal. 2D nonces operate on `tx.sender`'s streams regardless of execution authority. A delegated tx consumes the delegate's stream, not the delegator's.
- **Guarantors (`guarantors.md`)**: reinforces the stream-advances-on-inclusion invariant (§5). No design change.
- **Validity windows (`validity-windows.md`)**: orthogonal. A future-valid tx holds its stream position until it lands or expires; does not block other streams.

---

## 14. Comparison

- **vs. ERC-4337** — 4337 packs key+seq into a single `uint256` (192+64) because it lives above the protocol and can't change tx state shape. EIP-8141 uses two independent envelope fields (`uint256` + `uint64`). 8141 wins on universal EOA coverage (no smart-contract wallet, no bundler, no EntryPoint). The design here does not inherit from 4337.
- **vs. Tempo** — Both are clean-slate native designs; both converge on `(nonce_key: uint256, nonce: uint64)` as the right shape. EIP-8141 preserves programmable VERIFY, the PQ roadmap, and frame composability; Tempo bakes 2D nonces into a fixed-primitive tx type.
- **vs. ERC-on-top-of-8141** — Wins on universal coverage (no account-type fragmentation) and one-shot inclusion.
- **vs. `lanesRoot` (earlier draft)** — Same user-facing behavior. Zero account-encoding change. Reuses existing contract-storage machinery. Matches the EIP-4788 / EIP-2935 precedent that core devs have already accepted.

---

## 15. Non-goals

- Validity windows — separate proposal (`validity-windows.md`).
- Cross-stream atomicity — one tx commits to exactly one stream by envelope shape.
- Lane pruning / reclamation — separate EIP.
- Stream-key labels, session-key binding conventions — future ERC.
- Nonce enumeration RPC — wallets own their key inventory.

---

## 16. Spec delta summary

Against the current EIP-8141 draft:

1. Add envelope field `nonce_key: uint256` (default 0), positioned immediately before the existing `nonce` field.
2. Reinterpret `tx.nonce: uint64` as the sequence within the stream selected by `nonce_key`.
3. Deploy immutable `NonceLaneRegistry` at a reserved address; pin address + expected code hash at fork activation.
4. Consensus pre-tx rule: for `nonce_key > 0`, system-call `REGISTRY.check(sender, key, tx.nonce)` + `REGISTRY.advance(sender, key)`. For `nonce_key == 0`, legacy path unchanged.
5. Stream advances on successful inclusion regardless of VERIFY outcome (normative invariant).
6. First-use cost: SSTORE-from-zero (20 000 gas with EIP-2929 refinements) applied inside the registry. No separate constant.
7. Expose `tx.nonce_key` on the default-code tx-context surface.
8. Require sponsor signatures to bind `(sender, nonce_key, tx.nonce)`.
9. New RPC method `eth_getTransactionCountByKey(address, nonce_key, blockTag)`.
10. Mempool policy: `MAX_ACTIVE_STREAMS_PER_SENDER = 16`, per-lane RBF, block-invalidation rule.

**One envelope field. One system contract. Zero new opcodes. Zero new precompiles. Zero new frame modes. Zero account-encoding changes. Zero sighash rule changes.** Every EOA gets protocol-native parallel nonce streams on the day EIP-8141 activates; the restrictive mempool tier admits them cleanly; consensus bounds lane allocation via SSTORE-from-zero; account code retains full visibility into the stream key via existing tx-context mechanisms.

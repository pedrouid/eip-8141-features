# Research — Deep Dive on the 14 Open Questions

_Author: Claude. Scratch doc, not indexed on the site. Works through the open questions from `plan.md` with options, tradeoffs, and a pick per question._

## Validity Windows

### Q1. Max-future-deferral horizon

How far into the future can a tx schedule `valid_after` and still be admissible to the public mempool?

**Options**: 1 hour; 24 hours; tiered; time+count cap.

**Pick: tiered.** Public mempool 1 hour; expansive 24 hours; direct-to-builder unlimited.

**Rationale.** Public mempool pressure stays bounded; subscriptions route through private tiers (which they need anyway for fee negotiation); same-day scheduling gets a path.

### Q2. `GOSSIP_THRESHOLD`

When do future-valid txs start propagating through p2p instead of sitting locally?

**Pick: 60 seconds (5 slots).** Local-only until `(valid_after - block.timestamp) <= GOSSIP_THRESHOLD`, then gossip.

**Rationale.** 60 s is ample for propagation (~12 s typical full). Bounds bandwidth cost. Simple rule.

### Q3. RPC error codes

Four snake_case names at a contiguous JSON-RPC code block:

| Name | Code | Meaning |
|---|---|---|
| `validity_window_too_far_future` | -32010 | `valid_after` beyond tier horizon |
| `validity_window_not_yet_valid` | -32011 | `valid_after` future, node doesn't buffer |
| `validity_window_already_expired` | -32012 | `valid_before <= block.timestamp` |
| `validity_window_reverse` | -32013 | `valid_after >= valid_before` (both non-zero) |

## 2D Nonces

### Q4. Where lane state lives (no account encoding change)

**Background.** Earlier pick (`lanesRoot` as a new account RLP field) rejected: changing account encoding affects every RLP parser, every state-root computation, EIP-161, archive-node decoding. Core-dev review would push back hard.

**Options reconsidered**:
- Account RLP field `lanesRoot` — rejected, scope too big.
- Reserved namespace in sender's storage — EOAs run default code; collisions with custom code make it fragile.
- System contract at a reserved address (EIP-4788 / EIP-2935 pattern) — consensus pre-tx call reads/advances the registry.
- Protocol-owned global trie — even more invasive.

**Pick: `NonceLaneRegistry` system contract.**

```solidity
contract NonceLaneRegistry {
    mapping(address => mapping(uint256 => uint64)) private lanes;

    function check(address sender, uint256 key, uint64 seq) external view returns (bool);
    function advance(address sender, uint256 key) external;  // SYSTEM_ADDRESS only
    function get(address sender, uint256 key) external view returns (uint64);
}
```

Deployed at reserved address, fork-coordinated, immutable per Q13.

**Pre-tx flow**:

```
if tx.nonce_key == 0:
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    REGISTRY.advance(tx.sender, tx.nonce_key)
```

**Avoids**: account RLP change, outer state-trie change, EIP-161 amendment, new witness format, archive decoding changes.

**Adds**: one system contract, a pre-tx system-call hook, lane state as SSTORE slots in the registry.

**Rationale.** Twice-accepted precedent (EIP-4788 beacon roots, EIP-2935 historical hashes). Familiar ground for core-dev review. Engineering cost bounded.

### Q5. Pre- or post-state-tree transition?

**Pick: ships now on current MPT; forward-compatible by construction.**

**Rationale.** Lane state is ordinary contract storage. Verkle migration is identical to any other contract's storage — no bespoke work. Nothing needs to wait for state-tree transition.

### Q6. VOPS state-growth budget

**Math (registry storage).**
- SSTORE-from-zero = 20 000 gas (Q7).
- Slot entry: 32-byte key + 32-byte value + MPT overhead ≈ 100 bytes per lane.
- Adversarial: 30 Mgas / 20k = 1 500 lanes/block. 7 200 blocks/day = ~1 GB/day.
- Realistic: cap × 1 M active accounts = 16 M slots one-time ≈ 1.6 GB total.

**Pick.** ~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate.

**Rationale.** VOPS slicing treats registry slots as ordinary storage witnesses. If growth exceeds budget, raise first-use cost via a standard SSTORE-accounting amendment.

### Q7. `LANE_ALLOCATION_COST`

**Pick: collapses into SSTORE-from-zero (20 000 gas).**

**Rationale.** With Q4's registry design, first-use of a non-zero lane is literally SSTORE-from-zero in the registry. No separate constant. Earlier 25 000 figure (calibrated against CREATE) no longer applies — it assumed lane allocation was account-level; now it's storage-level, so SSTORE schedule is the right reference and nothing to retune.

### Q8. Sequence-overflow

`tx.nonce = 2^64 - 1` is the last valid sequence on a lane; subsequent txs are consensus-invalid. Sender migrates to a new `nonce_key`.

**Rationale.** Replay protection never breaks. Real-world impossible to hit (~585 billion years at 1 tx/sec). Clean spec text.

## Permissions

### Q9. `execution_authority` in base EIP or separate?

**Options**: base EIP-8141; separate EIP in same fork; permissions EIP only.

**Pick: separate EIP in same fork.**

**Rationale.** `execution_authority` is useful beyond delegation:
- Multi-sig flows where one signer initiates and others authorize execution.
- Account migration flows where a new account's authority is approved by the old account.
- Recovery flows where a guardian's approval lets execution run as the recovered account.

Bundling into base 8141 bloats an already-large spec. Bundling into permissions hides the primitive. A dedicated small EIP keeps base clean, makes primitive discoverable, lets other features depend on it.

### Q10. Does guarantors land in the same fork?

**Options**: yes bundled; no defer; primitive yes, manager-as-guarantor deferred.

**Pick: primitive in fork; manager-as-guarantor deferred to permissions v2.**

**Rationale.** Decouples guarantor design iteration from permissions timeline. Primitive is independently valuable for ERC-20 paymasters, privacy flows, complex AA validation. Manager-as-guarantor needs more thought on manager-side gas-pool economics (staking, slashing, fee recovery) than the guarantor PR itself.

### Q11. SENDER-revert policy

**Options**: atomic revert (tx reverts, delegation not consumed); settlement-on-any-outcome (delegation consumed regardless).

**Pick: atomic revert.**

**Rationale.**
- Matches caller expectations.
- Prevents griefing: malicious delegate can't "burn" delegations by submitting failing redemptions.
- Simpler mental model.
- Delegate can retry — correct behavior; delegation remains valid, just needs valid execution.
- One-shot semantics live in the `one_shot_salt` caveat, not the revert policy.

### Q12. Size caps

PQ context: ML-DSA 2.4–4.6 KB; SLH-DSA 7.8–49 KB; hybrid additive.

| Param | v1 | Rationale |
|---|---|---|
| `MAX_PROOF_SIZE` | **8192** B | ML-DSA + classical+PQ hybrids; rules out largest SPHINCS+ (acceptable v1). |
| `MAX_CAVEAT_COUNT` | **8** | Matches canonical vocabulary. Composable via combinators in v2. |
| `MAX_BUNDLE_SIZE` | **16384** B | Proof + metadata. Generous but bounded. |

Validation gas budget: v1 fits in ~300k per redemption.

### Q13. Manager upgrade model

**Pick: immutable; upgrades via new reserved address at future forks.**

**Rationale.** Matches ERC-4337 EntryPoint precedent. Avoids centralizing upgrade authority. Migration is explicit and user-visible. Old delegations stay valid against the manager they were signed against. Prevents rug-pull scenarios.

**Migration.** Existing delegations retain validity until expiry/revocation. New delegations sign against v2. Wallets surface migration as a first-class step.

### Q14. Revocation indexing

**Pick: both with defined roles.**

| Responsibility | Manager | Wallet |
|---|---|---|
| Authoritative state | ✓ | |
| Events for indexers | ✓ | |
| Canonical `revoke` / `revokeAll` | ✓ | |
| Local inventory for offline UX | | ✓ |
| Pre-confirmation display | | ✓ |
| Cross-device sync | | ✓ |

**Manager events (v1)**:

```solidity
event DelegationRegistered(
    address indexed delegator, address indexed delegate,
    bytes32 indexed delegationHash,
    bytes32 delegationDigest, uint256 expiry);

event DelegationRedeemed(
    bytes32 indexed delegationHash,
    address indexed delegator, address indexed delegate,
    bytes32 callHash);

event DelegationRevoked(
    bytes32 indexed delegationHash,
    address indexed delegator, bytes32 reason);
```

**Rationale.** Manager events are authoritative (cross-device, audits, chain indexing). Wallet cache is needed for offline display, pre-confirmation, PQ-migration prompts. "Manager = truth, wallet = convenience."

## Summary of picks

| # | Question | Pick |
|---|---|---|
| 1 | Max future-deferral horizon | Tiered: 1 h / 24 h / unlimited |
| 2 | `GOSSIP_THRESHOLD` | 60 seconds |
| 3 | RPC error codes | 4 codes at JSON-RPC -32010..-32013 |
| 4 | Lane-state location | `NonceLaneRegistry` system contract (EIP-4788 pattern) |
| 5 | State-tree transition | Forward-compat via contract storage; ships on current MPT |
| 6 | VOPS state-growth budget | ~2 GB/year; ~1 GB/day adversarial |
| 7 | `LANE_ALLOCATION_COST` | Collapses into SSTORE-from-zero |
| 8 | Sequence-overflow | Invalid at `2^64 - 1`; migrate to new key |
| 9 | `execution_authority` placement | Separate EIP in same fork |
| 10 | Guarantors in same fork | Primitive yes; manager-as-guarantor v2 |
| 11 | SENDER-revert policy | Option A (atomic) |
| 12 | Size caps | proof 8 KB, caveats 8, bundle 16 KB |
| 13 | Manager upgrade | Immutable; new reserved address per fork |
| 14 | Revocation indexing | Manager events + wallet cache |

## What's still uncertain

Two picks flagged as "best-guess pending data":

- **Q6 VOPS budget** — back-of-envelope math; needs cross-client benchmarks. Registry design makes this easier to measure (per-slot pressure).
- **Q12 size caps** — PQ landscape still evolving; 8 KB right for ML-DSA, under-spec for large SPHINCS+.

Q7 resolved by construction (SSTORE-from-zero is known, tuned). Everything else has principled basis independent of benchmarking data.

## What this changes in the plan

Once these picks are accepted, `plan.md` "Open questions" collapses from 14 to 2 (Q6, Q12). The other 12 pin into the proposals during the edit pass.

**Key architectural revision**: Q4 moved from "add `lanesRoot` to account RLP" to "deploy `NonceLaneRegistry` system contract (EIP-4788 pattern)." Eliminates account-encoding changes. Q5 and Q7 simplify as a consequence.

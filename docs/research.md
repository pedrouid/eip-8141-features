# Research — Deep Dive on the 14 Open Questions

*Author: Claude. Scratch doc, not indexed on the site. Working through the open questions from `plan.md` with options, tradeoffs, and a recommended pick per question.*

Questions are numbered to match the order in `plan.md` §"Open questions to resolve before implementation." Each section: restated question → options → recommended pick → rationale.

---

## Validity Windows

### Q1. Exact max-future-deferral horizon

**Question.** How far into the future can a tx schedule its `valid_after` and still be admissible to the public mempool?

**Tradeoffs.** Too short kills subscriptions and scheduled payments. Too long lets the mempool fill with speculative future-valid txs.

**Options.**
- **A. 1 hour** (current draft). Covers short intents (auctions, swaps, reveal-phase) but kills same-day scheduling.
- **B. 24 hours.** Allows day-of scheduling. Mempool holds each tx up to a day.
- **C. Tiered.** 1 hour for public mempool, 24 hours for expansive tier, unbounded direct-to-builder.
- **D. Time + count cap.** Unbounded horizon but cap active future-valid txs per sender (e.g., 4).

**Pick: C (tiered).** Public mempool caps at **1 hour**; expansive/private tier at **24 hours**; direct-to-builder unlimited.

**Rationale.** Public mempool pressure stays bounded; subscriptions route through private tiers (which they need anyway for fee negotiation); same-day scheduling gets a clean path; aligns with the general tier model of EIP-8141.

---

### Q2. Exact `GOSSIP_THRESHOLD`

**Question.** When do future-valid txs start propagating through p2p instead of sitting locally?

**Options.**
- **A. Gossip immediately on admission.** Simple; burns bandwidth on txs that can't execute yet.
- **B. Local-only until near activation.** Then gossip.
- **C. Adaptive**: gossip within `2 × slot_time × log(peer_count)` of activation, sized to network.
- **D. Node-policy choice**, no protocol rule.

**Pick: B with a fixed parameter.** Local-only until `(valid_after - block.timestamp) <= GOSSIP_THRESHOLD`. **`GOSSIP_THRESHOLD = 60 seconds`** (5 slots).

**Rationale.** 60 s is ample for a well-connected mempool to reach most peers (typical full propagation ~12 s). Bounds bandwidth cost. Simple rule, no adaptive complexity. The 5 s I mentioned earlier in the plan was too tight against 12 s block times.

---

### Q3. RPC error-code naming finalization

**Question.** Canonical error code names and JSON-RPC numeric codes for validity-window rejections.

**Pick.** Four snake_case names + a contiguous JSON-RPC code block:

| Name | Code | Meaning |
|---|---|---|
| `validity_window_too_far_future` | -32010 | `valid_after` beyond node's deferral horizon |
| `validity_window_not_yet_valid` | -32011 | `valid_after` in the future and node doesn't buffer |
| `validity_window_already_expired` | -32012 | `valid_before <= block.timestamp` |
| `validity_window_reverse` | -32013 | `valid_after >= valid_before` (both non-zero) |

**Rationale.** Descriptive names help wallets render user-safe messages. JSON-RPC `-32010..-32013` is a contiguous block inside the server-error reserved range, leaving room for future window-related codes.

---

## 2D Nonces

### Q4. Where does lane state live? (revised — no account encoding change)

**Question.** How are non-zero lane sequences stored without modifying the account RLP?

**Background.** The earlier pick (`lanesRoot` as a new account RLP field) was rejected: changing the account encoding is a consensus-paradigm shift that affects every RLP parser, every state-root computation, EIP-161 empty-account semantics, archive-node decoding, and historical queries. Core-dev review would push back hard.

**Options reconsidered.**
- **A. Account RLP field `lanesRoot`.** _Rejected_ — scope is too big for the value delivered.
- **B. Reserved namespace in sender's own storage.** EOAs run default code in EIP-8141; default code and future custom account code could collide with the reserved slot pattern. Fragile.
- **C. System contract at a reserved address.** Follows the EIP-4788 (beacon roots) and EIP-2935 (historical block hashes) pattern. Lane state lives in an ordinary contract's `storageRoot`. Consensus pre-tx system-call reads/advances the registry.
- **D. Protocol-owned global trie.** A brand-new trie type — even more invasive than A.

**Pick: C (system contract `NonceLaneRegistry` at a reserved address).**

**Specification details.**

```solidity
contract NonceLaneRegistry {
    // sender => nonce_key => sequence
    mapping(address => mapping(uint256 => uint64)) private lanes;

    function check(address sender, uint256 key, uint64 seq) external view returns (bool);
    function advance(address sender, uint256 key) external;  // callable only by SYSTEM_ADDRESS
    function get(address sender, uint256 key) external view returns (uint64);
}
```

- Deployed at a reserved address (e.g., `0x000F...NN`), fork-coordinated.
- Immutable per Q13. Upgrades ship as new reserved addresses at future forks.
- `advance` callable only by a system-pseudo-address (the same pattern EIP-4788 uses).

**Consensus pre-tx flow.**

```
if tx.nonce_key == 0:
    // legacy path, byte-for-byte identical to today
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    REGISTRY.advance(tx.sender, tx.nonce_key)
```

**What this avoids.**
- No account RLP change.
- No outer state-trie shape change.
- No EIP-161 amendment.
- No new witness format — storage witnesses against the registry work out of the box.
- No archive-node decoding changes.

**What this adds.**
- One system contract (precedent: EIP-4788, EIP-2935).
- A consensus rule that pre-tx system-calls the registry for non-zero keys.
- Lane state shows up in the registry's `storageRoot` as ordinary SSTORE slots.

**Rationale.** Twice-accepted precedent (EIP-4788 beacon roots, EIP-2935 historical hashes) means core-dev review is on familiar ground. The engineering cost is bounded: deploy a contract, add a pre-tx system-call hook, reuse existing storage-witness machinery. Lane state migrates to Verkle identically to any other contract storage.

---

### Q5. Pre- or post-state-tree transition?

**Question.** Does 2D nonces wait for Verkle/state-tree transition, or ship on the current MPT?

**Pick: ships now on current MPT; forward-compatible by construction.**

**Rationale.** Lane state lives in an ordinary contract's `storageRoot` (see Q4). Its migration path to Verkle is identical to every other contract's storage — no bespoke work. Nothing about 2D nonces needs to wait for or coordinate with the state-tree transition.

The earlier framing ("forward-compatible commitment") is now automatic because we're not introducing a new commitment type at all.

---

### Q6. VOPS state-growth budget

**Question.** What state-growth rate should 2D nonces produce, and is it within VOPS's budget?

**Back-of-envelope math (revised for registry storage).**
- Each non-zero lane occupies one SSTORE slot in `state[REGISTRY].storage`.
- First-use cost: SSTORE-from-zero = **20 000 gas** (Q7).
- Slot entry: 32-byte key + 32-byte value = 64 bytes trie leaf, plus MPT overhead ≈ **~100 bytes per lane**.
- Adversarial upper bound: 30 Mgas / 20k = 1 500 lanes/block. At 7 200 blocks/day = 10.8 M lanes/day ≈ **~1 GB/day adversarial**.
- Realistic: mempool cap `MAX_ACTIVE_STREAMS_PER_SENDER = 16` across 1 M active accounts = 16 M lane slots, one-time allocation ≈ **~1.6 GB total**.

**Pick.** Budget **~2 GB total state growth** for legitimate use within the first year after activation, accepting up to **~1 GB/day** under sustained adversarial conditions before SSTORE-from-zero + mempool caps saturate attackers.

**Rationale.** Registry storage grows like any other contract's. VOPS slicing treats registry storage slots as ordinary storage-witness entries; pressure is per-slot, not per-new-subtrie. If real-world growth exceeds budget during rollout, the spec can raise first-use cost via a standard SSTORE-accounting amendment.

---

### Q7. `LANE_ALLOCATION_COST` cross-client benchmark

**Question.** What gas value for first-use lane allocation?

**Pick: collapses into SSTORE-from-zero = 20 000 gas.**

**Rationale.** With Q4's registry-contract design, first-use of a non-zero lane is literally an SSTORE-from-zero inside the registry. No separate `LANE_ALLOCATION_COST` constant needed — the existing SSTORE cost schedule (including EIP-2929 warm/cold refinements) applies directly.

This is a strict simplification over the earlier `LANE_ALLOCATION_COST = 25000` pick. The 25 000 figure was calibrated against `CREATE` because lane allocation was then account-level. Now it's storage-level, so SSTORE's schedule is the right reference and there's no new constant to specify or retune.

---

### Q8. Sequence-overflow migration path

**Question.** What happens when `state[sender].nonces[nonce_key]` reaches `2^64 - 1`?

**Context.** `2^64 ≈ 1.8 × 10^19`. At 1 tx/sec continuously on one lane, 585 billion years to overflow. Not a practical concern but spec must close the case.

**Options.**
- **A. Consensus-invalid at max.** Any tx with `tx.nonce = 2^64 - 1` is the last allowed; subsequent txs on that lane revert.
- **B. Saturate.** Tx succeeds, nonce doesn't advance. Breaks replay protection.
- **C. Wrap to 0.** Breaks replay protection.
- **D. Migrate to `uint128` if ever approached.**

**Pick: A (consensus-invalid at max).** The sequence `2^64 - 1` is valid as the final transaction on that lane; the sender must migrate to a new `nonce_key` for further activity.

**Rationale.** Replay protection never breaks. Real-world impossible to hit. Clean spec text.

---

## Permissions

### Q9. `execution_authority` in the base EIP or a separate EIP?

**Question.** Structural — where does this primitive live?

**Options.**
- **A. In base EIP-8141.** Bundled with the core frame-tx spec.
- **B. Separate EIP in same fork as base 8141.** Dedicated small EIP; permissions cites it.
- **C. In permissions EIP only.** Not available to other features.

**Pick: B (separate EIP in same fork).**

**Rationale.** `execution_authority` is useful beyond delegated permissions:
- Multi-sig flows where one signer initiates and others authorize execution.
- Account migration flows where a new account's authority is approved by an old account.
- Recovery flows where a guardian's approval lets execution run as the recovered account.

Bundling it into base 8141 bloats that already-large spec. Bundling it into permissions hides the primitive. A small dedicated EIP keeps the base clean, makes the primitive discoverable, and lets other features depend on it without depending on permissions.

---

### Q10. Does guarantors land in the same fork?

**Question.** Is PR #11555 (derekchiang) in the first AA fork alongside EIP-8141?

**Options.**
- **A. Yes, bundled.** Unlocks manager-as-guarantor for v1 permissions.
- **B. No, defer to a follow-on fork.** Permissions v1 ships without guarantor path.
- **C. Guarantors ship as a primitive, manager-as-guarantor deferred.** Generic guarantor primitive in fork; permissions' specific use of it in v2.

**Pick: C (generic guarantor primitive in fork, manager-as-guarantor in v2 of permissions).**

**Rationale.** Decouples guarantor design iteration from permissions timeline. The guarantor primitive is independently valuable for:
- ERC-20 gas paymasters with shared-state reads.
- Privacy flows with nullifier reads.
- Complex AA validation.

Manager-as-guarantor requires more work on manager-side gas-pool economics (staking, slashing, fee recovery) than the guarantor PR itself. Splitting the timeline lets the primitive ship when ready without blocking on manager economics.

---

### Q11. SENDER-revert policy (Option A vs B)

**Question.** What happens if a SENDER frame reverts during a delegated redemption?

**Options.**
- **A. Atomic revert.** Entire tx reverts; delegation not consumed; delegate pays gas for the attempt.
- **B. Settlement-on-any-outcome.** SENDER reverts roll back SENDER effects but delegation is consumed; `consumeAndFinalize` still runs.

**Pick: A (atomic) for v1.**

**Rationale.**
- Matches caller expectations (atomic tx semantics).
- Prevents griefing: a malicious delegate can't "burn" a delegation by submitting a known-failing redemption.
- Simpler mental model for users, wallets, hardware-wallet prompts.
- A delegate can retry a failed redemption — this is correct behavior because the delegation is still valid; the delegate just needs to present valid execution.
- Delegators who want one-shot semantics attach the `one-shot salt` caveat from the v1 canonical vocabulary, not the SENDER-revert policy.

Tradeoff: v1 accepts that a delegation can be "retried" indefinitely until expiry. This is a feature for session-key flows, not a bug.

---

### Q12. `MAX_PROOF_SIZE`, `MAX_CAVEAT_COUNT`, `MAX_BUNDLE_SIZE`

**Question.** Concrete size caps for delegation validation.

**PQ context.**
- ML-DSA (Dilithium) signatures: 2.4 – 4.6 KB.
- SLH-DSA (SPHINCS+) signatures: 7.8 – 49 KB depending on parameters.
- Hybrid classical+PQ: additive.

**Picks.**

| Parameter | v1 value | Rationale |
|---|---|---|
| `MAX_PROOF_SIZE` | **8192 bytes (8 KB)** | Accommodates ML-DSA and hybrid classical+PQ; rules out the largest SPHINCS+ variants (acceptable for v1, since wallets use the smaller variants). |
| `MAX_CAVEAT_COUNT` | **8** | Matches the canonical caveat vocabulary from the wallet-dev feedback. Composable via combinator caveats in v2. |
| `MAX_BUNDLE_SIZE` | **16384 bytes (16 KB)** | Bundle = delegation metadata + caveats + proof. 8 KB proof + 8 KB metadata is generous but bounded. |

**Validation-gas budget consistent with these caps.** With `MAX_PROOF_SIZE = 8 KB` and typical ML-DSA verify cost (~5M gas in reference implementations, target ~200k for native precompile), v1 validation fits in a 300k-gas budget per redemption.

**Rationale.** PQ-safe, bounded validation cost, matches canonical caveat set, future-expandable at later forks via spec amendment.

---

### Q13. Manager upgrade governance post-v1

**Question.** How do manager upgrades work after v1 ships?

**Options.**
- **A. Immutable v1; upgrades = new reserved address at future fork.** Multiple versions coexist; migration is explicit.
- **B. Upgradeable via fork-governed admin.** Single reserved address, fork replaces bytecode.
- **C. Per-account opt-in.** Each account points at its preferred manager version.

**Pick: A (immutable, fork-governed deployment of new versions).**

**Rationale.**
- Matches ERC-4337 EntryPoint precedent (each EntryPoint version at its own address; accounts declare which EntryPoint they trust).
- Avoids centralizing upgrade authority in any party.
- Migration is explicit and user-visible (wallets prompt "migrate your delegations to Manager v2").
- Old delegations stay valid against the manager they were signed against — this is critical for long-lived authorizations.
- Prevents the "rug-pull" scenario where a fork-governed admin silently changes delegation semantics.

**Migration story.** Accounts with active delegations against Manager v1 retain them until expiry or revocation. New delegations sign against v2. Wallets surface migration as a first-class step during PQ transitions or known-vulnerability responses.

---

### Q14. Revocation indexing responsibility (manager vs wallets)

**Question.** Who provides the indexed list of a user's active delegations for revocation UI?

**Options.**
- **A. Manager-only.** Manager emits events; wallets query manager storage.
- **B. Wallet-only.** Wallet tracks delegations in local storage.
- **C. Both, with defined roles.**

**Pick: C (both, with defined roles).**

**Roles.**

| Responsibility | Manager | Wallet |
|---|---|---|
| Authoritative record of delegation state | ✓ | |
| Emits events for indexers | ✓ | |
| Canonical revocation entry point (`revoke`, `revokeAll`) | ✓ | |
| Local inventory for offline UX | | ✓ |
| Pre-confirmation display of pending delegations | | ✓ |
| Cross-device sync via backup | | ✓ |
| Third-party audit / indexer integration | Uses events | |

**Manager event schema (v1).**

```solidity
event DelegationRegistered(
    address indexed delegator,
    address indexed delegate,
    bytes32 indexed delegationHash,
    bytes32 delegationDigest,
    uint256 expiry
);

event DelegationRedeemed(
    bytes32 indexed delegationHash,
    address indexed delegator,
    address indexed delegate,
    bytes32 callHash
);

event DelegationRevoked(
    bytes32 indexed delegationHash,
    address indexed delegator,
    bytes32 reason
);
```

**Rationale.** Manager events are the authoritative source (needed for cross-device recovery, third-party audits, chain-indexed lookups). Wallet cache is needed for offline display, pre-confirmation flows, and PQ-migration prompts. Separation matches the "manager = truth, wallet = convenience" pattern used elsewhere (e.g., 4337 bundler events + wallet state).

---

## Summary of picks

| # | Question | Pick |
|---|---|---|
| 1 | Max future-deferral horizon | Tiered: 1h public / 24h expansive / unlimited direct-to-builder |
| 2 | `GOSSIP_THRESHOLD` | 60 seconds |
| 3 | RPC error codes | 4 codes at JSON-RPC -32010..-32013 |
| 4 | Lane-state location | `NonceLaneRegistry` system contract at reserved address (EIP-4788 pattern). No account encoding change. |
| 5 | State-tree-transition timing | Inherits contract-storage migration; no bespoke work |
| 6 | VOPS state-growth budget | ~2 GB/year legitimate; ~1 GB/day adversarial; registry storage slots |
| 7 | `LANE_ALLOCATION_COST` | Collapses into SSTORE-from-zero (20 000 gas); no separate constant |
| 8 | Sequence-overflow | Consensus-invalid at `2^64 - 1`; migrate to new `nonce_key` |
| 9 | `execution_authority` placement | Separate EIP in same fork as base 8141 |
| 10 | Guarantors in same fork | Primitive yes; manager-as-guarantor deferred to permissions v2 |
| 11 | SENDER-revert policy | Option A (atomic) |
| 12 | Size caps | proof 8 KB, caveats 8, bundle 16 KB |
| 13 | Manager upgrade model | Immutable; new reserved address per fork |
| 14 | Revocation indexing | Both: manager = authoritative events, wallet = local cache |

---

## What's still uncertain

Two of the 14 picks deserve flagging as "best-guess pending further data":

- **Q6 VOPS budget** — back-of-envelope math; needs real cross-client benchmarks to confirm the budget is right-sized. The registry-contract design makes this easier to reason about (pressure is per-storage-slot) but doesn't eliminate the need for measurement.
- **Q12 size caps** — PQ signature landscape is still evolving; if a smaller PQ scheme wins, 8 KB proof is overspec'd. If SPHINCS+ wins, 8 KB is underspec'd. Revisit once PQ selection stabilizes.

Q7 is now resolved by construction (SSTORE-from-zero is a known, tuned value). Everything else has a principled basis independent of benchmarking data.

---

## What this changes in the plan

Once these picks are accepted, the "Open questions" section of `plan.md` collapses into 2 remaining unknowns (Q6 and Q12 pending data). The other 12 can be pinned directly into the corresponding proposals during the edit pass.

**Key architectural revision:** Q4 moved from "add `lanesRoot` to account RLP" to "deploy `NonceLaneRegistry` system contract at reserved address (EIP-4788 pattern)." This eliminates account-encoding changes entirely. Q5 and Q7 simplify as a consequence.

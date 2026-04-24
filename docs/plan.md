# Plan — Changes to the Three Proposals Based on Core-Dev and Wallet-Dev Feedback

_Author: Claude. Scratch doc, not indexed on the site. Actionable plan derived from `coredev-feedback.md` and `walletdev-feedback.md`, with decisions resolved in `research.md`._

---

## Summary of the two reviews

**Where they agree:**

1. The revisions fixed the major correctness bugs. The proposals are now in the right design family.
2. **Sequencing**: ship validity windows first, 2D nonces second (needs state design), permissions third (narrow v1 or its own EIP).
3. Each proposal should explicitly classify which flows are restrictive-tier / guarantor-gated / expansive-only.
4. Post-quantum migration is a real concern, especially for long-lived permissions signed with classical keys.
5. Predictability matters more than feature richness — under-specified provider/client behavior will fragment adoption.

**Where they differ (and how to reconcile):**

- Core-dev emphasizes VOPS/FOCIL/state-representation/fork-scope discipline.
- Wallet-dev emphasizes RPC/SDK/hardware-wallet/display/revocation UX.
- The reconciliation is that each proposal grows a **spec appendix** covering both axes — core-dev wants the state and consensus answers pinned; wallet-dev wants the RPC/error-code/display answers pinned. Neither is optional for shipping.

---

## Sequencing decision

**Validity windows → 2D nonces → Permissions.**

Both reviewers independently recommend this order. Locking it in:

- **Validity windows** ship in the same fork as base EIP-8141 if possible. Minimal blast radius, maximum user-safety upside.
- **2D nonces** ship once state encoding + VOPS treatment are settled. Explicitly do not block validity windows on 2D-nonce state design.
- **Permissions** become a follow-on EIP that depends on `execution_authority` as a published primitive, unless core-dev and wallet-dev consensus emerges that native permissions belong in the same fork.

The plan below assumes this ordering when describing priorities.

---

## Decisions resolved from research

All 14 open questions from the previous iteration of this plan have been worked through in `research.md`. 11 are pinned; 3 remain pending cross-client benchmarking data. Table below; each decision is folded into the per-proposal sections that follow.

| # | Question | Decision |
| - | --- | --- |
| 1 | Max future-deferral horizon | Tiered: 1 h public / 24 h expansive / unlimited direct-to-builder |
| 2 | `GOSSIP_THRESHOLD` | 60 seconds (5 slots) |
| 3 | RPC error codes | 4 codes at JSON-RPC `-32010..-32013` |
| 4 | Lane-state location | `NonceLaneRegistry` system contract at reserved address (EIP-4788 pattern). No account encoding change. |
| 5 | State-tree transition timing | Inherits contract-storage migration; no bespoke work |
| 6 | VOPS state-growth budget | ~2 GB/yr legitimate; ~1 GB/day adversarial — **pending benchmarks** |
| 7 | `LANE_ALLOCATION_COST` | Collapses into SSTORE-from-zero (20 000 gas); no separate constant |
| 8 | Sequence-overflow policy | Consensus-invalid at `2^64 - 1`; sender migrates to a new `nonce_key` |
| 9 | `execution_authority` placement | Separate EIP in same fork as base 8141 |
| 10 | Guarantors in same fork | Primitive yes; manager-as-guarantor deferred to permissions v2 |
| 11 | SENDER-revert policy | Option A (atomic revert; delegation not consumed) |
| 12 | Size caps | proof 8 KB, caveats 8, bundle 16 KB — **pending PQ landscape** |
| 13 | Manager upgrade model | Immutable; new reserved address per future fork |
| 14 | Revocation indexing | Both: manager = authoritative events, wallet = local cache |

---

## Validity Windows — changes needed (small)

`validity-windows.md` is the closest to shippable. Focused tightening only.

### Consensus / semantics

1. **Pin the zero sentinel unambiguously**: `valid_after == 0` means no lower bound; `valid_before == 0` means no upper bound. Remove the "degenerate always-expired" framing in §2.
2. **Reverse-window rule**: if both fields are non-zero and `valid_after >= valid_before`, the tx is consensus-invalid.
3. **Strict vs inclusive**: lock to `block.timestamp > valid_after` (exclusive lower) and `block.timestamp < valid_before` (exclusive upper).

### Mempool policy (node-level)

4. **Tiered deferral horizon** (Q1): public mempool admits txs with `valid_after - now <= 1 hour`; expansive tier admits up to `24 hours`; direct-to-builder has no horizon cap. Txs beyond a tier's horizon route through higher tiers or fail with `validity_window_too_far_future`.
5. **`GOSSIP_THRESHOLD = 60 seconds`** (Q2). Future-valid txs are local-only until `(valid_after - block.timestamp) <= 60`, then enter normal gossip.
6. **Replacement semantics while future-valid**: RBF still applies; a replacement must also satisfy its own validity window.
7. **Eviction rule on expiry**: drop immediately on new head.

### RPC / error codes (Q3)

8. Four canonical error names at JSON-RPC codes `-32010..-32013`:
   - `validity_window_too_far_future` (`-32010`)
   - `validity_window_not_yet_valid` (`-32011`)
   - `validity_window_already_expired` (`-32012`)
   - `validity_window_reverse` (`-32013`)

### Wallet display guidance (new appendix)

9. Add a short display-guidance appendix (non-normative) covering: local-time rendering, relative-duration labels, warnings on unusually long windows, warnings on already-expired or reverse windows before signing.

### Out of scope (pin explicitly)

10. Block-number bounds, recurring/cron execution, on-chain schedulers — already in non-goals; keep.

**Estimated delta**: ~10 small spec edits, one new appendix. No structural rewrite.

---

## 2D Nonces — changes needed (medium-large)

`2d-nonces.md` is directionally correct but underspecifies state, VOPS, and provider behavior. The state appendix is the blocking item; Q4 pins its shape.

### State representation (no account encoding change)

1. **Lane-state location (Q4)**. Deploy `NonceLaneRegistry` at a reserved address, following the EIP-4788 (beacon roots) / EIP-2935 (historical block hashes) pattern. Storage layout: `mapping(address => mapping(uint256 => uint64))`. Consensus pre-tx flow for non-zero keys: system-call `REGISTRY.check(sender, nonce_key, tx.nonce)`, then `REGISTRY.advance(sender, nonce_key)`. For `nonce_key == 0` the legacy path is byte-for-byte identical to today. **No account RLP change. No state-trie shape change. No EIP-161 amendment.**
2. **State-tree transition (Q5)**. Registry storage migrates to Verkle identically to any other contract's `storageRoot`. No bespoke work, no separate migration path. Ships on current MPT; forward-compatibility is automatic.
3. **Witness format**: standard storage witness into `state[REGISTRY].storageRoot` for the specific `(sender, nonce_key)` slot. Reuses existing storage-witness machinery.
4. **First-use cost (Q7)**: ordinary SSTORE-from-zero (20 000 gas, with EIP-2929 warm/cold refinements) applied inside the registry. No `LANE_ALLOCATION_COST` constant needed.
5. **Pruning/reclamation**: none in v1. Reclamation is a separate EIP.
6. **Sequence-overflow (Q8)**: `tx.nonce = 2^64 - 1` is the last valid sequence on a lane; subsequent txs on that lane are consensus-invalid. Sender migrates to a new `nonce_key`.
7. **Contract creation address derivation**: uses the legacy `nonce` field (= `nonces[0]`) only; non-zero lanes do not participate. Make explicit in §3.
8. **Registry immutability**: fork-deployed, immutable, upgrades via new reserved address at future forks (matches Q13 for the DelegationManager).

### VOPS profile (new, Q6 budget pending)

9. Lane-state validation reads from `state[REGISTRY].storage` — one slot per active `(sender, nonce_key)`. The VOPS slice for a non-zero-lane tx extends by one storage slot in the registry. Uses standard storage-witness machinery; no new witness type.
10. **State-growth budget** (Q6, pending benchmarks): ~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate attackers. Retune via standard SSTORE-accounting amendment if real data exceeds budget.
11. A VOPS attester validates a non-zero-lane tx by proving the registry's slot for `(sender, nonce_key)` matches `tx.nonce - 1` — no full-state lookup needed.

### FOCIL cross-client rules (new)

12. Pin the **exact RBF tuple**: `(sender, nonce_key, tx.nonce)`.
13. Pin **pending-cap semantics**: default `MAX_ACTIVE_STREAMS_PER_SENDER = 16`.
14. Pin **future-valid interaction**: a future-valid tx reserves its sequence on its own lane; does not block other lanes.
15. Pin **lane-allocation admission**: a tx that allocates a new lane pays SSTORE-from-zero inside the registry; mempool tracks the allocation alongside its normal sender-state.
16. Pin **block-invalidation rule**: when a block increments any `(sender, nonce_key)` lane, pending txs at the pre-increment sequence on that lane are invalidated.

### RPC / provider surface (expand §8)

17. Add **pending-count-per-key** variant.
18. Add **tx-lookup by `(sender, nonce_key, nonce)`** endpoint.
19. Add **replacement status per key** endpoint.
20. Pin distinct error codes: `lane_not_found`, `too_many_active_streams`.
21. Specify **`eth_estimateGas` behavior** for first-use lane allocation (must surface the SSTORE-from-zero surcharge inside the registry call).
22. Specify **simulation** that includes mempool pending state on the relevant key.

### Wallet integration appendix (new, non-normative)

23. Wallet lane-namespace recommendation table (default / dapp session / recovery / automation / ephemeral) as guidance, not standard.
24. Hardware-wallet display requirements: readable lane labels, first-use warnings, unknown-lane warnings.
25. Default-lane fallback guidance for wallets that do not support 2D nonces.

### Explicit acknowledgment of cross-proposal interactions (tighten §10)

26. Make the "stream advances on inclusion regardless of VERIFY outcome" rule normative in this proposal (it's the right home). Currently framed as clarification; promote to a numbered invariant.

**Estimated delta**: large. The state appendix alone is ~500 words. The VOPS and FOCIL sections add another ~400 each. The RPC surface doubles.

---

## Permissions — changes needed (largest; split into two EIPs)

Two structural decisions from research drive the rewrite:

- **Q9**: `execution_authority` becomes its own EIP in the same fork as base 8141, usable by multi-sig, migration, and recovery flows independently of permissions.
- **Q10**: the guarantor primitive lands in-fork, but **manager-as-guarantor** is deferred to permissions v2. Shared-state caveats in v1 route through expansive/private tiers; no manager gas-pool economics in v1.

### Factor `execution_authority` out (structural, Q9)

1. Promote `execution-authority.md` to an **independent EIP** in the same fork as base 8141. Permissions cites it as a prerequisite rather than absorbing its spec inline.
2. Retain the permissions-side section on how delegation uses `execution_authority`, but cite the standalone EIP rather than re-specifying.

### Fork-scope inclusion list (new section)

3. Add an explicit inclusion list for a permissions-inclusive fork:
   - `execution_authority` EIP (separately, per Q9).
   - Consensus-coordinated **immutable** DelegationManager (Q13) — address, code hash, deployment, no in-place upgrades.
   - `tx_context.sender_frames` surface.
   - `consumeAndFinalize` post-op hook with revert semantics.
   - Restrictive-tier permissions profile (stateless caveats only).
   - VOPS profile for manager state.
   - Guarantor primitive yes; manager-as-guarantor no (Q10).
   - ERC-7715 adoption for wallet RPC.
4. If any item is not in scope for the permissions fork, the proposal should state which downstream capability is unavailable until that item ships.

### Post-op semantics (Q11)

5. **Atomic revert (Option A)**: if any SENDER frame reverts in a delegated redemption, the entire tx reverts; `consumeAndFinalize` does not run; the delegation is not consumed. One-shot semantics live in the `one-shot salt` caveat, not the revert policy.
6. `consumeAndFinalize` gas cap: **50 000**.
7. If `consumeAndFinalize` itself reverts: entire tx reverts; sender's tx-level nonce still consumed per the 2D-nonces stream-advances-on-inclusion rule.

### Canonical caveat vocabulary for v1 (new §)

8. Adopt the wallet-dev recommended v1 caveat set (`MAX_CAVEAT_COUNT = 8` per Q12):
   - target allowlist
   - function-selector allowlist
   - max native value
   - max ERC-20 amount
   - expiry
   - one-shot salt
   - frame-count limit
   - exact-call commitment
9. **Arbitrary caveat contracts are expansive-tier-only** in v1. Restrictive-tier permissions use the canonical vocabulary exclusively.
10. Reserve registry indices for these canonical caveats so wallets and hardware wallets can render them without parsing opaque calldata.

### Revocation, events, and indexing (new §, Q14)

11. Canonical manager events: `DelegationRegistered(delegator, delegate, delegationHash, delegationDigest, expiry)`, `DelegationRedeemed(delegationHash, delegator, delegate, callHash)`, `DelegationRevoked(delegationHash, delegator, reason)`. All include indexed topics for chain-indexed lookups.
12. Require the manager to expose deterministic lookup by delegation hash.
13. Require `revoke(delegationHash)` and `revokeAll(delegator)` as canonical manager entry points.
14. Wallet SDK requirement (non-normative appendix): `wallet_getPermissions`, per-dapp revoke UI, emergency revoke-all, local cache of granted/received delegations.

### PQ migration appendix (new, Q12)

15. Require **explicit expiry** on every v1 delegation. A delegation with `expiry == 0` is invalid.
16. Pin a **canonical delegation-digest domain separator** that includes a scheme/version tag so PQ migration can distinguish classical from PQ delegations.
17. Document the PQ-migration workflow: after an account migrates to a PQ authorization scheme, wallets must surface "revoke old permissions" as a first-class step.
18. Size caps (Q12, pending PQ landscape): `MAX_PROOF_SIZE = 8 192` bytes, `MAX_CAVEAT_COUNT = 8`, `MAX_BUNDLE_SIZE = 16 384` bytes.

### Mempool classification table (new §)

19. Add an explicit table the SDK layer consumes:

| Permission flow                                               | Mempool tier                                                        |
| ------------------------------------------------------------- | ------------------------------------------------------------------- |
| One-hop, canonical-caveat, execution-only                     | Restrictive (public)                                                |
| Canonical caveat with shared-state read                       | Expansive/private in v1 (manager-as-guarantor deferred per Q10)     |
| Any of: re-delegation, stateful caveats, payment delegation   | v2                                                                  |
| Arbitrary caveat contracts                                    | Expansive/private                                                   |

20. Expose the classification as a wallet query so dapps know whether a granted permission can be redeemed publicly or requires a private route.

### VOPS profile (new §)

21. Restrictive-tier validation surface for the manager: manager code, delegation-nonce slot for the specific delegation being validated, revocation-registry slot for the specific delegation being validated. Nothing else.
22. Caveat-contract storage reads are outside VOPS in v1 (since manager-as-guarantor is deferred per Q10).

### Manager upgrade model (Q13)

23. Manager is **immutable**. Upgrades ship as new reserved addresses at future forks. Existing delegations remain valid against the manager version they were signed against.
24. Wallets surface manager migration as a first-class step at each upgrade fork; users may need to revoke old delegations and re-sign against the new manager for continuing use.

### Hardware-wallet requirements (new §)

25. All envelope fields (`nonce_key`, `valid_after`, `valid_before`) parsed natively on-device.
26. Delegation digests use typed structured data following the canonical caveat format.
27. Blind-signing warnings for caveat types outside the canonical vocabulary.
28. Role fields (delegate, delegator, payer) shown explicitly on-device. Guarantor role omitted from v1 hardware display (no manager-as-guarantor per Q10).

### Cut from v1

29. Re-delegation chains — v2.
30. Stateful caveats — v2.
31. Payment delegation — v2.
32. Third-party guarantors and manager-as-guarantor — v2 (Q10).
33. Arbitrary caveat contracts in restrictive tier — expansive-only.

**Estimated delta**: large. Structural split into two EIPs (execution-authority + permissions). At least 5 new sections in permissions.

---

## Cross-cutting additions (apply to all three)

### Mempool-tier classification header

Every proposal should open with a short table naming which flows land in which tier. Already partially present; make it uniform across all three files.

### PQ-compatibility note

Add a one-paragraph PQ-compatibility note to each proposal's interaction section:

- Validity windows — positive, reduces timestamp-reading code paths.
- 2D nonces — positive, supports ephemeral signers and recovery-lane isolation.
- Permissions — positive if `validateAuth` stays crypto-agnostic, risky for long-lived classical delegations without explicit expiry/revocation (addressed by the PQ migration appendix above).

### FOCIL-compatibility note

Add a one-paragraph FOCIL-compatibility note similarly, citing which attester-facing invariants each proposal depends on.

### Cross-proposal rule: stream advance on inclusion

Pin in `2d-nonces.md` and cite in `permissions.md` and `guarantors.md`. Currently stated in `2d-nonces.md` §4 but should be normative, not clarifying.

---

## Remaining uncertainties

Two decisions are flagged as "best guess pending data." All others are pinned.

| # | Question | Reason still open |
| - | --- | --- |
| 6 | VOPS state-growth budget | Back-of-envelope math; needs real cross-client benchmarks to confirm the budget is right-sized. Registry-contract design makes this easier to measure (pressure is per-storage-slot) but doesn't eliminate the need. |
| 12 | Size caps (proof/caveat/bundle) | PQ signature landscape still evolving; 8 KB proof is right for ML-DSA, under-spec for large SPHINCS+ variants. |

Q7 (`LANE_ALLOCATION_COST`) was previously flagged; it is now resolved by construction — first-use cost collapses into SSTORE-from-zero (20 000 gas) inside the registry, with no separate constant to tune.

Neither remaining item blocks proposal edits: the starting values are concrete enough to specify. Both are expected to be retuned once cross-client benchmarks and PQ selection stabilize.

---

## Suggested order of work

1. **Validity windows**: apply the ~10 tightenings above + new wallet-display appendix. All decisions pinned. Target: close to ready-to-submit as a standalone EIP.
2. **Execution authority EIP**: extract `execution-authority.md` into a standalone EIP per Q9. Small, self-contained, unblocks permissions.
3. **Guarantor primitive alignment**: converge with derekchiang's PR #11555. The primitive lands in-fork per Q10; manager-as-guarantor doesn't.
4. **2D nonces state appendix**: write the state-representation subsection using the `NonceLaneRegistry` system-contract design from Q4 (EIP-4788 pattern, no account encoding change). This is the previous blocking gate; now much smaller scope.
5. **2D nonces VOPS + FOCIL + RPC surface expansion**: once registry design is pinned, the rest is a fan-out.
6. **Permissions v1 narrowing**: cut to the canonical caveat vocabulary, add fork-scope inclusion list, pin post-op semantics, add revocation interface, add PQ-migration appendix, lock manager-as-guarantor to v2.

The sequencing matches both reviewers' independent recommendation: do not bundle permissions with base EIP-8141 unless the full fork-scope inclusion list is in.

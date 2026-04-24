# Plan — Changes to the Three Proposals Based on Core-Dev and Wallet-Dev Feedback

_Author: Claude. Scratch doc, not indexed on the site. Actionable plan derived from `coredev-feedback.md` and `walletdev-feedback.md`, with decisions resolved in `research.md`._

## Summary of the two reviews

**Both reviewers agree:**

1. The revisions fixed the major correctness bugs.
2. **Sequencing**: validity windows first, 2D nonces second (needs state design), permissions third (narrow v1 or its own EIP).
3. Each proposal should explicitly classify flows as restrictive / guarantor-gated / expansive-only.
4. Post-quantum migration is a real concern, especially for long-lived permissions signed with classical keys.
5. Predictability beats feature richness — under-specified provider/client behavior fragments adoption.

**They differ on emphasis:**

- Core-dev emphasizes VOPS/FOCIL/state-representation/fork-scope discipline.
- Wallet-dev emphasizes RPC/SDK/hardware-wallet/display/revocation UX.

Each proposal grows a spec appendix covering both axes.

## Sequencing decision

**Validity windows → 2D nonces → Permissions.**

- Validity windows ship in the same fork as base EIP-8141 if possible. Minimal blast radius, maximum user-safety upside.
- 2D nonces ship once state encoding + VOPS treatment are settled. Do not block validity windows on 2D-nonce state design.
- Permissions become a follow-on EIP depending on `execution_authority` as a published primitive.

## Decisions resolved from research

14 open questions worked through in `research.md`. 12 pinned; 2 remain pending cross-client benchmarking data.

| # | Question | Decision |
| - | --- | --- |
| 1 | Max future-deferral horizon | Tiered: 1 h public / 24 h expansive / unlimited direct |
| 2 | `GOSSIP_THRESHOLD` | 60 seconds |
| 3 | RPC error codes | 4 codes at JSON-RPC `-32010..-32013` |
| 4 | Lane-state location | `NonceLaneRegistry` system contract (EIP-4788 pattern). No account encoding change. |
| 5 | State-tree transition | Inherits contract-storage migration |
| 6 | VOPS state-growth budget | ~2 GB/yr legitimate; ~1 GB/day adversarial — **pending benchmarks** |
| 7 | `LANE_ALLOCATION_COST` | Collapses into SSTORE-from-zero (20 000 gas) |
| 8 | Sequence-overflow | Consensus-invalid at `2^64 - 1`; migrate to new `nonce_key` |
| 9 | `execution_authority` placement | Separate EIP in same fork as base 8141 |
| 10 | Guarantors | Generic primitive yes; manager-as-guarantor deferred to permissions v2 |
| 11 | SENDER-revert policy | Option A (atomic; delegation not consumed) |
| 12 | Size caps | proof 8 KB, caveats 8, bundle 16 KB — **pending PQ landscape** |
| 13 | Manager upgrade model | Immutable; new reserved address per future fork |
| 14 | Revocation indexing | Both: manager authoritative events, wallet local cache |

## Validity Windows — changes needed (small)

### Consensus / semantics
1. Pin zero-sentinel unambiguously: `valid_after == 0` and `valid_before == 0` both mean no bound.
2. Reverse-window (`valid_after >= valid_before`, both non-zero) is consensus-invalid.
3. Strict inequalities: `block.timestamp > valid_after`, `< valid_before`.

### Mempool policy
4. Tiered deferral horizon: 1 h public / 24 h expansive / unlimited direct. Beyond tier horizon → `validity_window_too_far_future`.
5. `GOSSIP_THRESHOLD = 60 s`; future-valid held locally until within 60 s of `valid_after`.
6. Replacement while future-valid: RBF applies; replacement must satisfy its own window.
7. Expiry: drop immediately on new head.

### RPC / error codes
8. Four JSON-RPC error codes at `-32010..-32013` (`too_far_future`, `not_yet_valid`, `already_expired`, `reverse`).

### Wallet display (non-normative appendix)
9. Local-time rendering, relative duration, warnings on long or invalid windows.

### Out of scope
10. Block-number bounds, cron execution, on-chain schedulers.

**Delta**: ~10 small edits, one appendix. No structural rewrite.

## 2D Nonces — changes needed (medium)

Underspecifies state and VOPS. The state appendix is the blocking item; Q4 pins the shape.

### State representation (no account encoding change)
1. Deploy `NonceLaneRegistry` at reserved address (EIP-4788 / EIP-2935 pattern). `mapping(address => mapping(uint256 => uint64))`. Consensus pre-tx: system-call `REGISTRY.check` + `REGISTRY.advance` for non-zero keys. Legacy path for key 0. **No account RLP change. No state-trie shape change. No EIP-161 amendment.**
2. Registry storage migrates to Verkle like any other contract's storage.
3. Witnesses: standard storage proof against registry's `storageRoot`.
4. First-use cost: SSTORE-from-zero (20 000 gas). No `LANE_ALLOCATION_COST` constant.
5. Pruning/reclamation: none in v1.
6. Sequence-overflow: `tx.nonce = 2^64 - 1` last valid on lane.
7. Contract-creation derivation uses legacy `nonce` only.
8. Registry immutable; upgrades via new reserved address at future forks.

### VOPS profile (Q6 budget pending)
9. Lane validation reads from `state[REGISTRY].storage` — one slot per `(sender, nonce_key)`. Standard storage-witness machinery.
10. State-growth budget (pending benchmarks): ~2 GB/yr legitimate; ~1 GB/day adversarial.
11. A VOPS attester proves the registry slot matches `tx.nonce - 1`.

### FOCIL cross-client rules
12. RBF tuple: `(sender, nonce_key, tx.nonce)`.
13. Pending cap: `MAX_ACTIVE_STREAMS_PER_SENDER = 16`.
14. Future-valid tx reserves its sequence on its own lane; does not block others.
15. Lane-allocation admission: tx pays SSTORE-from-zero inside the registry.
16. Block-invalidation: block increments any `(sender, nonce_key)` → pending pre-increment txs invalidated.

### RPC / provider surface
17. Pending-count-per-key variant.
18. Tx-lookup by `(sender, nonce_key, nonce)`.
19. Replacement status per key.
20. Error codes: `lane_not_found`, `too_many_active_streams`.
21. `eth_estimateGas` surfaces SSTORE-from-zero surcharge for first-use.
22. Simulation includes mempool pending state on relevant key.

### Wallet integration (non-normative)
23. Lane-namespace recommendation (default / dapp session / recovery / automation / ephemeral).
24. Hardware-wallet display: readable labels, first-use warnings, unknown-lane warnings.
25. Default-lane fallback guidance.

### Cross-proposal normative invariant
26. Stream advances on inclusion regardless of VERIFY outcome.

**Delta**: medium. Main blocker — the registry-contract design — is now pinned.

## Permissions — changes needed (large; split into two EIPs)

Two structural decisions from research drive the rewrite:

- **Q9**: `execution_authority` is its own EIP in the same fork as base 8141, usable by multi-sig, migration, recovery independent of permissions.
- **Q10**: generic guarantor primitive in-fork; manager-as-guarantor deferred to permissions v2.

### Factor `execution_authority` out (structural, Q9)
1. Promote `execution-authority.md` to an independent EIP. Permissions cites it as a prerequisite.
2. Retain the permissions-side section on how delegation uses it.

### Fork-scope inclusion list
3. Permissions-inclusive fork includes: `execution-authority` EIP, immutable DelegationManager (address + code hash), `tx_context.sender_frames`, `consumeAndFinalize` post-op with revert semantics, restrictive-tier profile, VOPS profile, guarantor yes/no answer, ERC-7715.
4. If any item out of scope, state which downstream capability is unavailable.

### Post-op semantics (Q11)
5. Atomic revert: any SENDER revert reverts the whole tx; `consumeAndFinalize` does not run; delegation not consumed. One-shot via `one-shot salt` caveat.
6. `consumeAndFinalize` gas cap 50 000.
7. Post-op revert → whole tx reverts; sender's tx-level nonce still consumed per 2D-nonces rule.

### Canonical caveat vocabulary for v1
8. 8 types: target allowlist, selector allowlist, max native value, max ERC-20 amount, expiry, one-shot salt, frame-count limit, exact-call commitment.
9. Arbitrary caveat contracts are expansive-tier-only in v1.
10. Reserve registry indices for canonical caveats; wallets and hardware wallets can render them.

### Revocation, events, indexing (Q14)
11. Canonical manager events: `DelegationRegistered`, `DelegationRedeemed`, `DelegationRevoked`.
12. Manager entry points: `revoke(delegationHash)`, `revokeAll(delegator)`, `lookupDelegation`.
13. Wallet SDK: `wallet_getPermissions`, per-dapp revoke UI, emergency revoke-all, local cache.

### PQ migration
14. Non-zero `expiry` required on every v1 delegation.
15. Canonical delegation-digest domain separator carries scheme/version tag.
16. Manager handles large PQ proofs; `MAX_PROOF_SIZE` spec'd.
17. Migration workflow: "revoke old delegations" as first-class step after PQ transition.

### Mempool classification
18. Table exposed to SDK layer so dapps know public vs private routing.

### VOPS profile
19. Restrictive-tier validation surface: manager code, delegation-nonce slot, revocation slot for the specific delegation. Nothing else.
20. Caveat-contract storage reads outside VOPS in v1.

### Guarantor disclosure
21. If PR #11555 does not land: shared-state caveats are not restrictive-tier, manager-as-guarantor unavailable.

### Hardware-wallet requirements
22. Envelope fields parsed natively on-device.
23. Delegation digests: typed structured data.
24. Blind-signing warnings for non-canonical caveats.
25. Role fields (delegate, delegator, payer, guarantor) shown explicitly.

### Cut from v1
26. Re-delegation chains, stateful caveats, payment delegation, third-party guarantors, arbitrary caveats in restrictive tier — all v2.

**Delta**: large. Split into two EIPs (execution-authority + permissions).

## Cross-cutting additions

- **Mempool-tier classification header** on each proposal.
- **PQ-compatibility note** per proposal.
- **FOCIL-compatibility note** per proposal.
- **Cross-proposal rule**: stream advance on inclusion — pin in `2d-nonces.md`, cite in `permissions.md` and `guarantors.md`.

## Remaining uncertainties

| # | Question | Reason still open |
| - | --- | --- |
| 6 | VOPS state-growth budget | Back-of-envelope math; needs cross-client benchmarks. |
| 12 | Size caps (proof/caveat/bundle) | PQ signature landscape still evolving. |

Q7 (`LANE_ALLOCATION_COST`) now resolved by construction — SSTORE-from-zero inside the registry, no separate constant.

## Suggested order of work

1. **Validity windows**: apply the ~10 tightenings + wallet-display appendix. Close to ready-to-submit as a standalone EIP.
2. **Execution authority EIP**: extract as standalone per Q9. Small, self-contained, unblocks permissions.
3. **Guarantor primitive alignment**: converge with PR #11555. Primitive lands in-fork per Q10; manager-as-guarantor deferred.
4. **2D nonces state appendix**: using `NonceLaneRegistry` design. This is the previous blocking gate; now much smaller scope.
5. **2D nonces VOPS + FOCIL + RPC surface expansion**.
6. **Permissions v1 narrowing**: canonical caveat vocabulary, fork-scope inclusion, post-op semantics, revocation interface, PQ-migration appendix, manager-as-guarantor to v2.

Matches both reviewers' recommendation: do not bundle permissions with base EIP-8141 unless the full fork-scope inclusion list is in.

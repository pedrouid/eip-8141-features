# Delegated Permissions for EIP-8141

```
Status:             research draft (Phase-2 stretch)
Phase:              2
Alternative ID:     P2
Depends on:         EIP-8141 + a Phase-1 alternative + execution-authority EIP
Introduces:         DelegationManager, validateAuth, canonical caveat vocabulary,
                    DELEGATION_MARKER, consumeAndFinalize post-op
Shared appendices:  system-contracts, sighash-binding, mempool-tiers, pq-analysis
```

## 1. Status and scope

**This is not part of any Phase-1 proposal. It is a mapped future EIP path and should not be evaluated as a dependency of Phase 1.** Ships as a follow-on upgrade after a Phase-1 alternative has landed and stabilised.

> **Heads-up — this is a stretch.** Phase 1 is already a substantial upgrade. Permissions on top adds a third system contract, two new tx-scoped state variables, a core-invariant change to SENDER-frame `msg.sender`, default-code surface expansions, a canonical caveat vocabulary, and PQ-migration complexity. Bundling permissions with Phase 1 is **not recommended**. This doc exists so the design space is mapped, prerequisites are visible, and the path is concrete when the time comes.

ERC-7710/7715-style delegated permissions, narrow v1.

## 2. Motivation

Delegated permissions let one account (delegator) authorise another (delegate) to act on its behalf with caveats. Today the only path is smart-account wallets via ERC-4337/7710. This proposal lifts the primitive into EIP-8141 default code so every account can delegate without a bundler, without an EntryPoint, on the public mempool.

## 3. Priorities and non-goals

Priorities:

1. Follow-on upgrade. Phase 1 must land and stabilise first.
2. No envelope changes; delegation bound by its own signature chain (Class B; see [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)).
3. Narrow v1: one-hop, stateless caveats, execution-only.
4. Immutable canonical `DelegationManager`.
5. Crypto-agnostic via `validateAuth`. No ERC-1271.
6. PQ safety: explicit expiry, domain separator with version tag.

Non-goals (v2):

- Re-delegation chains, stateful caveats, payment delegation, manager-as-guarantor, restrictive-tier shared-state caveats, arbitrary caveats in restrictive tier.

## 4. Single-line spec delta

Default code gains one branch: `DELEGATION_MARKER` in VERIFY calldata → `STATICCALL DelegationManager.isAuthorizedView`; on success `APPROVE(execution)` sets `execution_authority = delegator`; SENDER frames run as the delegator. Post-op: `manager.consumeAndFinalize`.

## 5. Normative spec

### Dependencies

- **`execution-authority` EIP** ([`phase-2/execution-authority.md`](execution-authority.md)): hard prerequisite.
- **Phase-1 alternative**: whichever landed. Permissions reads on guarantors (every alternative); 2D nonces (P1.N, P1.NS, P1.NSW) for session-key flows; signer binding (P1.S, P1.NS, P1.NSW) for PQ delegators interacting with `permit`-style contracts; validity windows (P1.W, P1.NSW) for redemption-level expiry.

### Canonical DelegationManager (MUST)

Reserved address, immutable. Address + code hash pinned at upgrade activation; default code MUST verify the code hash before calling. Upgrades ship as new reserved addresses at future upgrades; existing delegations stay on their original manager.

_Why immutable:_ same rationale as `NonceLaneRegistry` and `PubkeyRegistry` (see [`appendix/system-contracts.md`](../appendix/system-contracts.md)), with the additional anti-rug-pull property that old delegations stay valid against the manager they were signed against.

### `validateAuth` primitive (MUST)

Default code MUST expose `validateAuth(bytes32 digest, bytes calldata proof) returns (bool)`. True iff `proof` demonstrates authorization. Account-agnostic, crypto-agnostic. No ERC-1271 reference.

### Delegation digest

```
delegationDigest = keccak256(
    "EIP8141-Delegation-v1",   // domain separator + PQ version tag
    chain_id, MANAGER_ADDRESS,
    delegator, delegate, caveats_root, salt, expiry
)
```

Signed offchain; verified by `delegator.validateAuth(delegationDigest, proof)`. Self-contained; no tx-sighash coverage needed (Class B). Redemption-to-tx binding comes from caveats evaluating signed SENDER frames.

### Default-code branch (MUST)

```
on VERIFY frame with DELEGATION_MARKER prefix:
  (delegate, bundle) = decode(calldata)
  (ok, data) = STATICCALL MANAGER.isAuthorizedView(
    self, delegate, tx_context.sender_frames, bundle)
  if ok: APPROVE(execution)  // execution_authority = self
  else:  revert
```

v1: delegation branch permits `APPROVE(execution)` only.

### Tx-context affordance (MUST)

Default code MUST expose `tx_context.sender_frames`, a read-only view over SENDER frames, so caveats evaluate signed action content. SENDER frames are not elided from `compute_sig_hash`.

### Validation + settlement (MUST)

Split because STATICCALL can't do stateful work.

- **Validation (static, VERIFY):** `isAuthorizedView(delegator, delegate, pendingFrames, bundle) -> (bool, validationData)`. Verifies `validateAuth`, delegate match, expiry, caveats, revocation.
- **Settlement (stateful, post-op):** `consumeAndFinalize(delegator, delegationHash, validationData)`. Nonce consumption + event emission. 50k gas cap.

SENDER-revert: atomic. Any revert reverts the tx; `consumeAndFinalize` MUST NOT run; delegation MUST NOT be consumed. _Rationale:_ atomic revert prevents griefing where a malicious delegate could burn delegations by submitting failing redemptions; the delegation remains valid and can be retried with valid execution.

### Canonical caveat vocabulary (MUST)

`MAX_CAVEAT_COUNT = 8` stateless types, each at a reserved address with known code hash:

| Caveat | Semantics |
|---|---|
| `target_allowlist` | `frames[*].target ∈ list` |
| `selector_allowlist` | `frames[*].data[0:4] ∈ list` |
| `max_native_value` | `sum(frames[*].value) ≤ limit` |
| `max_erc20_amount` | parsed `transfer`/`transferFrom` args ≤ limit |
| `expiry` | `block.timestamp < bound` |
| `one_shot_salt` | per-salt nonce consumed in `consumeAndFinalize` |
| `frame_count_limit` | `len(frames) ≤ limit` |
| `exact_call_commitment` | `keccak256(abi.encode(frames)) == bound` |

Arbitrary caveats are expansive-only in v1.

### Size caps (MUST NOT exceed)

`MAX_PROOF_SIZE = 8192` bytes; `MAX_CAVEAT_COUNT = 8`; `MAX_BUNDLE_SIZE = 16384` bytes. v1 validation fits in ~300k gas per redemption. Concrete PQ scheme sizes in [`appendix/pq-analysis.md`](../appendix/pq-analysis.md).

### PQ migration (MUST)

Non-zero `expiry` required. Domain separator MUST carry scheme/version tag. Wallets surface "revoke old delegations" during PQ transitions.

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- Cap enforcement: `MAX_CAVEAT_COUNT = 8`, `MAX_PROOF_SIZE = 8192`, `MAX_BUNDLE_SIZE = 16384` (also §5).
- Atomic revert: SENDER revert ⇒ `consumeAndFinalize` does not run; delegation not consumed (also §5).

### Node policy (SHOULD)

Per-flow tier classification:

| Flow | Tier |
|---|---|
| One-hop canonical-caveat execution-only | Restrictive |
| Canonical caveat with shared-state read | Expansive/private (manager-as-guarantor is v2) |
| Re-delegation, stateful caveats, payment delegation | v2 |
| Arbitrary caveats | Expansive/private |

VOPS profile (restrictive-tier surface): manager code, delegation-nonce slot for the delegation being validated, revocation slot for that delegation. Caveat-contract storage reads are outside VOPS in v1.

## 7. RPC and wallet surface

Manager events: `DelegationRegistered`, `DelegationRedeemed`, `DelegationRevoked` (indexed by hash, delegator, delegate). Entry points: `revoke`, `revokeAll`, `lookupDelegation`. Wallets cache locally; manager is authoritative. Manager events drive cross-device sync, audits, and chain indexing; the wallet cache covers offline display, pre-confirmation, and PQ-migration prompts. _Manager is truth, wallet is convenience._

ERC-7715 adopted verbatim.

## 8. Security and DoS analysis

- **Account consent.** A delegate cannot become `execution_authority` without the delegator's `validateAuth` accepting the proof. Atomic revert on SENDER failure prevents delegation burn.
- **Replay.** `salt` + `expiry` in the delegation digest, plus manager-side nonce tracking via the `one_shot_salt` caveat, bound replay surface.
- **Manager rug-pull.** Immutability + code-hash pinning prevent a malicious upgrade from invalidating signed delegations.
- **Caveat DoS.** Caveat-contract storage reads in v1 stay outside VOPS so caveats can read mutable state without VOPS regressions; restrictive-tier admission requires only stateless canonical caveats.
- **PQ size caps.** `MAX_PROOF_SIZE = 8192` is best-guess for lattice schemes + classical hybrids; under-spec for hash-based at L3+. See open questions.

## 9. Compatibility and interactions

- **vs. ERC-7710/7715:** 7710 requires smart-contract wallet; this puts delegation in default code. 7715 adopted verbatim.
- **vs. ERC-4337:** no bundler, no EntryPoint, public mempool.
- **vs. Tempo access keys:** programmable caveats vs fixed primitive.
- **vs. Phase-1 alternatives:** Phase 1 covers a fraction of "permissions UX" via 2D-nonce session keys, validity-window expiry, and guarantor-backed application contracts. Permissions closes the remaining `msg.sender = delegator` gap.

### Worked example — session redemption

Alice grants Bob `Game.play()` once. Frames: (0) VERIFY targeting Alice, default-code reads `DELEGATION_MARKER` and `APPROVE(execution)` sets `execution_authority = Alice`; (1) SENDER targeting Game, `play()` runs with `msg.sender = Alice`; (2) post-op `consumeAndFinalize`. `tx.sender = Bob` (Bob's nonce advances); Alice's nonce untouched.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q12 | Size caps (proof / caveat / bundle) | Best-guess; see [`docs/overview.md`](../overview.md). |

## 11. Appendix references

- [`phase-2/execution-authority.md`](execution-authority.md) for the hard prerequisite.
- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for shared system-contract patterns (`DelegationManager` follows the same shape).
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) Class B for the delegation-digest binding chain.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/pq-analysis.md`](../appendix/pq-analysis.md) for size caps and PQ migration.

## 12. Spec delta summary

Assuming a Phase-1 alternative shipped:

1. `execution-authority` EIP prerequisite.
2. Immutable `DelegationManager` at reserved address (address + code hash pinned).
3. Reserve `DELEGATION_MARKER` selector.
4. Default-code delegation branch; execution-only.
5. Default code exposes `validateAuth`.
6. `tx_context.sender_frames` affordance.
7. `consumeAndFinalize` post-op; atomic revert; 50k gas cap.
8. Canonical caveat vocabulary; arbitrary caveats expansive-only.
9. Size caps: 8 KB proof / 8 caveats / 16 KB bundle.
10. Canonical manager events and entry points.
11. PQ: non-zero expiry; domain separator with version tag.
12. Mempool: restrictive for canonical + execution-only.
13. VOPS profile for manager state.
14. ERC-7715.

Ships as a follow-on upgrade after a Phase-1 alternative has landed.

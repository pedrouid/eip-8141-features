# Delegated Permissions for EIP-8141

_Author: Claude. Scratch doc, not indexed on the site._

ERC-7710/7715-style delegated permissions, narrow v1. Depends on a standalone `execution-authority` EIP. Ships as a **v2 follow-on fork**. Per `evaluation.md`, ~85 % of permissions UX is deliverable via contract-layer work on base-fork primitives.

## Priorities

1. Follow-on fork, not same-fork.
2. No envelope changes; delegation bound by its own signature chain.
3. Narrow v1: one-hop, stateless caveats, execution-only.
4. No new opcodes, precompiles, frame modes.
5. Immutable canonical DelegationManager.
6. Account-agnostic / crypto-agnostic via `validateAuth`. No ERC-1271.
7. PQ safety: explicit expiry, domain separator with version tag.

## 1. Single-line spec delta

> Default code gains one branch: `DELEGATION_MARKER` in VERIFY calldata → `STATICCALL DelegationManager.isAuthorizedView`; on success `APPROVE(execution)` sets `execution_authority = self`; SENDER frames run as `self`. Post-op: `manager.consumeAndFinalize`.

## 2. v1 scope

| Feature | v1 | v2 |
|---|---|---|
| Hops | Single | Re-delegation chains |
| Caveats | 8 canonical stateless | Stateful quotas; arbitrary contracts restrictive-tier |
| Settlement | Nonce + events | After-hooks; stateful caveats |
| Approval | Execution only | Payment delegation |
| Guarantor | Generic only | Manager-as-guarantor |
| Shared-state caveats | Expansive/private | Restrictive via manager-as-guarantor |

## 3. `execution-authority` EIP dependency

Tx-scoped state + APPROVE-rule generalization letting SENDER frames run as an account other than `tx.sender`. Useful beyond delegation (multi-sig, migration, recovery); standalone EIP. Hard prerequisite.

## 4. Canonical DelegationManager

Reserved address, immutable. Address + code hash pinned at fork; default code verifies code hash before calling. Upgrades via new reserved addresses at future forks; existing delegations stay on their original manager.

## 5. `validateAuth` authorization primitive

Default code MUST expose `validateAuth(bytes32 digest, bytes calldata proof) returns (bool)`. True iff `proof` demonstrates authorization. Account-agnostic, crypto-agnostic. No ERC-1271 reference.

## 6. Delegation digest

```
delegationDigest = keccak256(
    "EIP8141-Delegation-v1",   // domain separator + PQ version tag
    chain_id, MANAGER_ADDRESS,
    delegator, delegate, caveats_root, salt, expiry
)
```

Signed offchain; verified by `delegator.validateAuth(delegationDigest, proof)`. Self-contained; no tx-sighash coverage needed. Redemption-to-tx binding comes from caveats evaluating signed SENDER frames.

## 7. Default-code branch

```
on VERIFY frame with DELEGATION_MARKER prefix:
  (delegate, bundle) = decode(calldata)
  (ok, data) = STATICCALL MANAGER.isAuthorizedView(
    self, delegate, tx_context.sender_frames, bundle)
  if ok: APPROVE(execution)  // execution_authority = self
  else:  revert
```

v1: delegation branch permits `APPROVE(execution)` only.

## 8. Tx-context affordance

Default code exposes `tx_context.sender_frames` — a read-only view over SENDER frames — so caveats evaluate signed action content. SENDER frames are not elided from `compute_sig_hash`.

## 9. Validation + settlement

Split because STATICCALL can't do stateful work.

- Validation (static, VERIFY): `isAuthorizedView(delegator, delegate, pendingFrames, bundle) -> (bool, validationData)`. Verifies `validateAuth`, delegate match, expiry, caveats, revocation.
- Settlement (stateful, post-op): `consumeAndFinalize(delegator, delegationHash, validationData)`. Nonce consumption + event emission. 50k gas cap.

SENDER-revert: atomic. Any revert reverts the tx; `consumeAndFinalize` does not run; delegation not consumed. One-shot semantics live in the `one_shot_salt` caveat.

## 10. Canonical caveat vocabulary (v1)

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

## 11. Size caps

`MAX_PROOF_SIZE = 8192` bytes (ML-DSA + hybrids). `MAX_CAVEAT_COUNT = 8`. `MAX_BUNDLE_SIZE = 16384` bytes. v1 validation fits in ~300k gas per redemption.

## 12. Revocation / events

Manager events: `DelegationRegistered`, `DelegationRedeemed`, `DelegationRevoked` (indexed by hash, delegator, delegate). Entry points: `revoke`, `revokeAll`, `lookupDelegation`. Wallets cache locally; manager is authoritative.

## 13. PQ migration

Non-zero `expiry` required. Domain separator carries scheme/version tag. Wallets surface "revoke old delegations" during PQ transitions. `MAX_PROOF_SIZE = 8192` handles ML-DSA + hybrids; larger SPHINCS+ needs expansive tier or a v2 cap.

## 14. Mempool classification

| Flow | Tier |
|---|---|
| One-hop canonical-caveat execution-only | Restrictive |
| Canonical caveat with shared-state read | Expansive/private (manager-as-guarantor is v2) |
| Re-delegation, stateful caveats, payment delegation | v2 |
| Arbitrary caveats | Expansive/private |

## 15. Fork-scope inclusion

Must include: `execution-authority` EIP; immutable DelegationManager; `tx_context.sender_frames`; `consumeAndFinalize` post-op; restrictive-tier profile; VOPS profile; ERC-7715; PQ appendix.

## 16. VOPS profile

Restrictive-tier surface: manager code, delegation-nonce slot for the delegation being validated, revocation slot for that delegation. Caveat-contract storage reads outside VOPS in v1.

## 17. Example — session redemption

Alice grants Bob `Game.play()` once:

| # | Mode | Target | Purpose |
|---|---|---|---|
| 0 | VERIFY | Alice | `DELEGATION_MARKER`; `APPROVE(execution)` sets `execution_authority = Alice` |
| 1 | SENDER | Game | `play()`; `msg.sender = Alice` |
| 2 | post-op | Manager | `consumeAndFinalize`; `DelegationRedeemed` emitted |

`tx.sender = Bob`; Bob's nonce advances; Alice's untouched.

## 18. Comparison

- vs. ERC-7710/7715: 7710 requires smart-contract wallet; this puts delegation in default code. 7715 adopted verbatim.
- vs. ERC-4337: no bundler, no EntryPoint, public mempool.
- vs. Tempo access keys: programmable caveats vs fixed primitive.
- vs. base fork: ~85 % of UX deliverable on base-fork primitives; this closes the `msg.sender = delegator` gap.

## 19. Spec delta summary

Assuming base AA fork shipped 2D nonces + validity windows + guarantors:

1. `execution-authority` EIP prerequisite.
2. Immutable DelegationManager at reserved address (address + code hash pinned).
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

Zero envelope / opcode / precompile / frame-mode changes. Ships as **v2 fork** after base AA fork. Bundling is against coredev recommendation.

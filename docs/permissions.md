# Delegated Permissions for EIP-8141

_Author: Claude. Scratch doc, not indexed on the site._

This proposal adds ERC-7710 / ERC-7715-style delegated permissions to EIP-8141, scoped to a narrow v1 and rewritten against the primitives (`sighash-binding.md`, `execution-authority.md`, `guarantors.md`), the two structural reviews (`coredev-feedback.md`, `walletdev-feedback.md`), and the decisions pinned in `research.md`.

**Position**: permissions should **not** be bundled with base EIP-8141 in the same fork. The coredev feedback was explicit on this point, and `evaluation.md` confirms that ~85% of the permissions UX is deliverable via contract-layer work on top of the base-fork primitives (2D nonces + validity windows + guarantors). This proposal specifies permissions as a **follow-on EIP** depending on a standalone `execution-authority` EIP, intended for a v2 fork after the base AA fork ships.

---

## Priorities

1. **Follow-on, not same-fork.** Ship as a v2 EIP once `execution_authority` is settled. Not blocked on the base AA-fork timeline.
2. **No envelope changes.** Delegation authority is bound by its own signature chain, not the tx sighash.
3. **Narrow v1.** One-hop delegation, stateless caveats, execution-only approval, canonical caveat vocabulary.
4. **No new opcodes. No new precompiles. No new frame modes.**
5. **Canonical DelegationManager is consensus-coordinated**, immutable, deployed at a reserved address.
6. **Account-agnostic and crypto-agnostic authorization** via `validateAuth(digest, proof)`. No ERC-1271 reference in the spec.
7. **Execution authority is the load-bearing primitive**, factored into its own EIP.
8. **PQ migration safety** baked into v1: explicit expiry required, domain separator carries scheme/version tag.

---

## 1. Single-line spec delta

> Default code gains one branch: when a VERIFY frame's calldata starts with `DELEGATION_MARKER`, it calls the canonical DelegationManager's `isAuthorizedView`. If authorized, it calls `APPROVE(execution)`, which via the execution-authority primitive sets `execution_authority = self`. Subsequent SENDER frames run with `msg.sender = self` (the delegator). Default code invokes `manager.consumeAndFinalize` as a post-op after successful SENDER execution.

---

## 2. v1 scope vs v2

| Feature | v1 | v2 (deferred) |
|---|---|---|
| Delegation hops | Single hop (A → B only) | Re-delegation chains (A → B → C) |
| Caveats | Canonical vocabulary of 8 types (stateless) | Stateful quotas, spend-limit counters, arbitrary caveat contracts in restrictive tier |
| Manager settlement | Validation + nonce/event consumption | After-hooks, stateful caveat consumption |
| Approval scope | Execution only | Payment delegation |
| Authorization primitive | `validateAuth(digest, proof)` | Same |
| Guarantor integration | Generic guarantor primitive available; **manager-as-guarantor deferred** | Manager-as-guarantor, third-party staked guarantors |
| Mempool tier for shared-state caveats | Expansive / private only | Restrictive via manager-as-guarantor |

Rationale: v1 is the smallest thing that unblocks wallet UX (session keys, one-shot grants, simple dapp permissions) while staying inside the restrictive mempool tier, avoiding the STATICCALL-vs-state-writes trap, and not dragging manager gas-pool economics into v1 review.

---

## 3. Dependency: `execution_authority` as a standalone EIP

`execution_authority` is a tx-scoped state variable + APPROVE-rule generalization that enables delegated-execution semantics. It is useful beyond delegated permissions (multi-sig initiation, account migration, recovery flows) and is factored into its own EIP per Q9 in `research.md`. Permissions v1 declares `execution-authority` as a hard prerequisite and does not re-specify it here.

In summary, execution-authority provides:
- Tx-scoped state `execution_authority: Optional[address]`.
- Generalized `APPROVE(execution)` rule: setting `execution_authority = X` when called from a VERIFY frame targeting `X`.
- SENDER frame execution rule: `msg.sender = execution_authority ?? tx.sender`.
- Account consent invariant: `X` can only become execution authority if a VERIFY frame targeting `X` approves it.

---

## 4. The canonical DelegationManager

Deployed at a consensus-coordinated reserved address, following the same pattern as the `NonceLaneRegistry` (2D nonces) and the EIP-4788 / EIP-2935 precedent.

**Pinned by the v2 fork:**
- **Address** — fixed at fork activation.
- **Code hash** — default code verifies the contract at the reserved address has the expected code hash before calling it.
- **Deployment** — manager bytecode deployed at or before fork activation; a tx before that with `DELEGATION_MARKER` reverts.
- **Upgrade model** — **immutable**. Upgrades ship as a new reserved address at a later fork, with explicit migration semantics. Existing delegations remain valid against the manager they were signed against.

Calling it a "convention" (as earlier drafts did) is wrong: if default code invokes a hardcoded address, clients must agree on that address to avoid consensus splits.

---

## 5. The `validateAuth` authorization primitive

EIP-8141 default code MUST expose:

```solidity
function validateAuth(bytes32 digest, bytes calldata proof) external view returns (bool);
```

Semantics: returns `true` iff `proof` demonstrates that the account authorizes `digest`. The account's implementation decides what "proof" means — secp256k1 signature, P256/WebAuthn assertion, multi-factor bundle, ZK proof, hash preimage, anything.

This is the only authorization-check interface EIP-8141 exposes. It is:

- **Account-agnostic** — EOAs (via default code) and smart contracts respond to the same call.
- **Crypto-agnostic** — no field, parameter, or vocabulary commits to any specific signature scheme.
- **ERC-1271-independent** — EIP-8141 does not require or reference ERC-1271. Accounts already implementing ERC-1271 can wrap it with a one-line adapter.

---

## 6. The delegation digest

The delegator signs an offchain canonical digest, never embedded in a specific transaction:

```
delegationDigest = keccak256(
    "EIP8141-Delegation-v1",   // domain separator + scheme/version tag for PQ migration
    chain_id,
    MANAGER_ADDRESS,
    delegator,
    delegate,
    caveats_root,              // hash commitment over caveat contracts + params
    salt,                      // per-delegation uniqueness
    expiry                     // unix timestamp; MUST be non-zero in v1
)
```

The domain separator and scheme/version tag are load-bearing for PQ migration — they allow the manager and wallets to distinguish classical-signed v1 delegations from future PQ-signed versions during revocation sweeps.

The signature over `delegationDigest` is verified by the manager via `delegator.validateAuth(delegationDigest, proof)`. The digest is **self-contained** — it does not depend on any specific transaction and does not need coverage by the tx sighash.

What binds a specific redemption to a specific transaction: **the caveats, evaluating signed SENDER frames** (see §8).

---

## 7. Default-code branch

Canonical default code gains one branch in its VERIFY path:

```
on VERIFY frame call:
    if calldata starts with DELEGATION_MARKER:
        (delegate, bundle) = decode(calldata)
        pendingFrames = tx_context.sender_frames
        (ok, validationData) = STATICCALL MANAGER_ADDRESS.isAuthorizedView(
            self,             // delegator
            delegate,
            pendingFrames,
            bundle
        )
        if ok: APPROVE(execution)    // sets execution_authority = self
        else:  revert
    else:
        // existing default-code authorization path, unchanged
```

Calling `APPROVE(execution)` triggers the execution-authority primitive: `execution_authority = self` (the delegator). Subsequent SENDER frames run with `msg.sender = self`.

**v1 constraint**: the delegation branch permits `APPROVE(execution)` only, not `APPROVE(payment)` or `APPROVE(both)`. Payment delegation is deferred to v2.

---

## 8. Protocol affordance: SENDER frames in tx context

`manager.isAuthorizedView` must receive the list of SENDER frames (or a canonical commitment over them) so caveats can evaluate signed action content.

Spec requirement: EIP-8141 default code exposes `tx_context.sender_frames` — a read-only view over the transaction's SENDER frames. SENDER frames are **not** elided from `compute_sig_hash`, so everything caveats inspect through this surface is covered by the tx signature (signed by the delegate).

The commitment format (full frame list vs. canonical hash + Merkle proofs per caveat) is an implementation choice pinned in the manager interface, not the protocol.

---

## 9. Validation and settlement: two phases

`STATICCALL`-only is insufficient because nonce consumption, event emission, and any stateful work cannot run inside `STATICCALL`. Split the manager interface into two phases.

### Phase 1 — validation (static, during VERIFY)

```solidity
function isAuthorizedView(
    address delegator,
    address delegate,
    SenderFrame[] calldata pendingFrames,
    bytes calldata delegationBundle
) external view returns (bool authorized, bytes memory validationData);
```

Pure read-only. Verifies:

- Delegator's signature over `delegationDigest` via `delegator.validateAuth(delegationDigest, proof)`.
- `delegate == tx.sender`.
- `block.timestamp < expiry`.
- Every stateless caveat's `check(pendingFrames, caveatParams)` returns true.
- Revocation registry read-only check.

Returns authorized + packed `validationData` for phase 2.

### Phase 2 — settlement (stateful, after SENDER frames)

```solidity
function consumeAndFinalize(
    address delegator,
    bytes32 delegationHash,
    bytes calldata validationData
) external;
```

Non-static. Performs:

- One-shot nonce consumption (if `one-shot salt` caveat is present).
- Canonical event emission: `DelegationRedeemed(...)`.

**v1 caveats are stateless**, so `consumeAndFinalize` is limited to nonce consumption and event emission. Stateful consumption (spend-limit counters, daily quotas) is v2 and requires a richer post-op path.

### SENDER-revert policy (atomic)

Per Q11 in `research.md`: if any SENDER frame reverts in a delegated redemption, **the entire tx reverts**, `consumeAndFinalize` does not run, and the delegation is not consumed. One-shot semantics live in the `one-shot salt` caveat, not the revert policy.

`consumeAndFinalize` is gas-capped at **50 000 gas** to prevent post-op griefing. If `consumeAndFinalize` itself reverts, the entire tx reverts; sender's tx-level nonce still consumed per the 2D-nonces stream-advances-on-inclusion invariant.

---

## 10. Canonical caveat vocabulary (v1)

The `MAX_CAVEAT_COUNT = 8` caveats admissible in restrictive-tier v1 redemptions:

| # | Caveat | Stateless? | Semantics |
|---|---|---|---|
| 1 | `target_allowlist` | yes | `pendingFrames[*].target ∈ allowlist` |
| 2 | `selector_allowlist` | yes | `pendingFrames[*].data[0:4] ∈ allowlist` |
| 3 | `max_native_value` | yes | `sum(pendingFrames[*].value) ≤ limit` |
| 4 | `max_erc20_amount` | yes | argument parse of `transfer` / `transferFrom` selectors ≤ limit |
| 5 | `expiry` | yes | `block.timestamp < bound` (complements delegation-digest expiry) |
| 6 | `one_shot_salt` | requires settlement | per-salt nonce consumed in `consumeAndFinalize` |
| 7 | `frame_count_limit` | yes | `len(pendingFrames) ≤ limit` |
| 8 | `exact_call_commitment` | yes | `keccak256(abi.encode(pendingFrames)) == bound` |

Each caveat implementation is a contract deployed at a reserved address (similar pattern to the manager itself); the manager knows their code hashes. Wallets and hardware wallets can render the parameters without parsing opaque calldata because the caveat type is identifiable from the deployed address.

**Arbitrary caveat contracts are expansive-tier-only in v1.** Restrictive-tier permissions use the canonical vocabulary exclusively. This is the main safety lever: wallets have a small, known set of caveats to render, users have a small set of concepts to understand, and manager state-surface is bounded.

---

## 11. Size caps

Per Q12 in `research.md`:

- `MAX_PROOF_SIZE = 8192` bytes (8 KB) — accommodates ML-DSA signatures and classical+PQ hybrids.
- `MAX_CAVEAT_COUNT = 8` — matches the canonical vocabulary.
- `MAX_BUNDLE_SIZE = 16384` bytes (16 KB) — delegation + caveats + proof.

Validation gas budget consistent with these caps: v1 delegation validation fits in a 300k-gas budget per redemption.

---

## 12. Revocation, events, and indexing

Per Q14 in `research.md`: split responsibility between manager (authoritative events) and wallets (local cache for offline UX).

**Canonical manager events:**

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

**Canonical manager entry points:**

- `revoke(bytes32 delegationHash)` — authorized by `validateAuth` against the delegator's account.
- `revokeAll(address delegator)` — bulk revocation authorized by `validateAuth` against the delegator's account.
- `lookupDelegation(bytes32 delegationHash) returns (DelegationState)` — deterministic lookup for indexers.

**Wallet SDK requirements** (non-normative):

- `wallet_getPermissions` (ERC-7715) for enumerating active delegations a wallet granted.
- Local cache of granted and received delegations for offline UX.
- Per-dapp revoke UI.
- Emergency revoke-all.
- PQ-migration warning on classical-signed delegations after account migrates to a PQ scheme.

---

## 13. PQ migration appendix

- **Explicit expiry required.** A v1 delegation with `expiry == 0` is invalid. Wallets MUST set a non-zero expiry.
- **Domain-separator scheme/version tag.** The `"EIP8141-Delegation-v1"` prefix in the delegation digest is load-bearing: wallets and indexers distinguish classical v1 delegations from future PQ-signed versions by parsing the prefix.
- **Migration workflow.** After an account migrates to a PQ authorization scheme (e.g., new `validateAuth` implementation accepting PQ proofs), wallets MUST surface "revoke old delegations" as a first-class step before the migration completes. Classical-signed delegations remain a quantum-vulnerability surface until explicitly revoked.
- **Proof size cap** (`MAX_PROOF_SIZE = 8192`) accommodates ML-DSA and hybrid signatures without breaching validation gas caps. Larger PQ schemes (SPHINCS+ high-parameter variants) require either a v2 cap increase or expansive-tier routing.

---

## 14. Mempool classification

| Permission flow | Mempool tier |
|---|---|
| One-hop, canonical-caveat, execution-only | **Restrictive (public)** |
| Canonical caveat with shared-state read | **Expansive/private in v1** (manager-as-guarantor deferred per Q10) |
| Re-delegation, stateful caveats, payment delegation | **v2** |
| Arbitrary caveat contracts | **Expansive/private** |

The classification is exposed to wallet SDKs (via `wallet_grantPermissions` response metadata or a companion RPC) so dapps know whether a granted permission can be redeemed publicly or requires a private route.

**Guarantor disclosure**: if PR #11555 (generic guarantor primitive) has landed in the base fork, shared-state caveats remain expansive-only in permissions v1 because manager-as-guarantor is deferred to permissions v2. Permissions v2 unlocks restrictive-tier shared-state caveats via manager-as-guarantor.

---

## 15. Public-mempool carve-outs for the manager

Per the coredev feedback, the spec must pin:

- **External calls** — the manager may call only caveat contracts from the canonical vocabulary. No arbitrary CALLs during validation.
- **Storage reads** — restricted to manager storage (delegation-nonce slot, revocation-registry slot for the specific delegation being validated) and the delegator's account surface. No other contract storage in restrictive tier.
- **Bundle/caveat/proof caps** — §11.
- **Warm/cold access** — all delegator-surface and manager-surface accounts treated as warm for validation accounting.
- **Invalidation rules** — revocation-state changes invalidate pending txs touching the revoked delegation.

---

## 16. VOPS profile

- **Restrictive-tier validation surface** for the manager: manager code, delegation-nonce slot for the specific delegation being validated, revocation-registry slot for the specific delegation being validated. Nothing else.
- Caveat-contract storage reads are outside VOPS in v1 (since manager-as-guarantor is deferred).
- Witness format: standard storage witness against the manager's `storageRoot`. No new proof type.

---

## 17. Examples

All examples below assume the execution-authority primitive: `tx.sender` is the delegate; `execution_authority` is the delegator once APPROVE(execution) is called.

### Example 1 — Simple session redemption

Alice grants Bob permission to call `Game.play()` once. Bob redeems:

| # | Mode | Target | Purpose |
|---|---|---|---|
| 0 | VERIFY | Alice | `DELEGATION_MARKER` + bundle → manager.isAuthorizedView (checks delegate == Bob, target_allowlist = {Game}, expiry ok, sig verified via Alice.validateAuth). Default code calls APPROVE(execution); `execution_authority = Alice`. |
| 1 | SENDER | Game | `play()`. Runs with `msg.sender = Alice`. |
| 2 | (post-op) | Manager | Default-code-invoked `consumeAndFinalize`. Consumes the `one_shot_salt` if present. Emits `DelegationRedeemed`. |

`tx.sender = Bob`; Bob's nonce advances; Alice's tx-level nonce untouched.

### Example 2 — Sponsored session redemption

Alice's delegation, Bob redeeming, Sponsor paying gas.

| # | Mode | Target | Purpose |
|---|---|---|---|
| 0 | VERIFY | Alice | Delegation check. `APPROVE(execution)` sets `execution_authority = Alice`. |
| 1 | VERIFY | Sponsor | Sponsor's default code verifies the sponsorship terms. Sponsor sig must bind `(delegationHash, frameHash)`. `APPROVE(payment)`. |
| 2 | SENDER | USDC | `transfer(Bob, amount)`. `msg.sender = Alice`. Caveats enforce `max_erc20_amount`. |
| 3 | (post-op) | Manager | `consumeAndFinalize`. |

Roles: `tx.sender = Bob` (signs, consumes own nonce), `execution_authority = Alice` (SENDER runs as), payer = Sponsor.

### Example 3 — Atomic batched actions

Alice pre-approves a DEX swap flow with a two-call caveat. Bob redeems:

| # | Mode | Target | Purpose |
|---|---|---|---|
| 0 | VERIFY | Alice | Delegation check with `target_allowlist = {USDC, DEX}` and `frame_count_limit = 2`. |
| 1 | SENDER | USDC | `approve(DEX, 100e6)`. `msg.sender = Alice`. |
| 2 | SENDER | DEX | `swap(USDC→ETH, 100e6)`. `msg.sender = Alice`. |
| 3 | (post-op) | Manager | `consumeAndFinalize`. |

If either SENDER frame reverts, the whole tx reverts and the delegation is not consumed (atomic-revert policy).

### Example 4 — Revocation

Alice calls `DelegationManager.revoke(delegationHash)` from her own account. Any future redemption of that delegation — by Bob or any downstream delegate — has `isAuthorizedView` return false because the revocation slot is set. Default code reverts the VERIFY frame. No protocol change needed beyond what's already in §12.

---

## 18. Interaction with other primitives

- **Sighash binding (`sighash-binding.md`)**: resolved. Bundle binding comes from the delegator's independent digest signature; SENDER frames (signed by the delegate) are visible to caveats through `tx_context.sender_frames`. No sighash rule change.
- **Execution authority (`execution-authority.md`)**: load-bearing. Factored into its own EIP.
- **Guarantors (`guarantors.md`)**: generic guarantor primitive available in v1 base fork; **manager-as-guarantor is permissions v2**. Shared-state caveats stay expansive-only in permissions v1.
- **2D nonces (`2d-nonces.md`)**: orthogonal. Delegate's nonce stream advances; delegator's tx-level nonce untouched. Session keys can dedicate non-zero lanes to specific dapps for isolation.
- **Validity windows (`validity-windows.md`)**: complementary. Delegation bundle carries `expiry` (application layer); the tx envelope's `valid_before` bounds each redemption attempt (protocol layer). Both useful.

---

## 19. Out of scope for v1

- **Re-delegation chains (A → B → C).** v2.
- **Stateful caveats** (spend-limit counters, rolling-window quotas). v2.
- **Payment delegation.** v2.
- **Manager-as-guarantor.** v2; v1 uses the generic guarantor primitive only if a third party commits.
- **Third-party staked guarantors** (non-manager). v2.
- **Arbitrary caveat contracts** in restrictive tier. Expansive/private only in v1.
- **ERC-7715 typed-permission schemas.** v1 carries them as opaque `permissionContext`; standardization is a separate ERC.

---

## 20. Fork-scope inclusion list

A permissions-inclusive fork must include all of:

- `execution_authority` EIP (standalone per Q9; prerequisite).
- Consensus-coordinated immutable DelegationManager at reserved address (address + code hash pinned).
- `tx_context.sender_frames` protocol affordance.
- `consumeAndFinalize` post-op hook with atomic-revert semantics.
- Restrictive-tier permissions profile (canonical caveat vocabulary, stateless).
- VOPS profile for manager state (§16).
- ERC-7715 adoption for wallet RPC.
- PQ migration appendix enforced in v1 (explicit expiry, domain separator).

If any item is not in scope for the permissions fork, specify which downstream capability is unavailable until that item ships.

---

## 21. Comparison

- **vs. ERC-7710/7715 today** — 7710 requires a deployed smart-contract wallet. This proposal puts delegation in default code, so every EOA is a delegator on activation day. 7715 is adopted verbatim as the wallet RPC.
- **vs. ERC-4337 session keys** — 4337 needs a bundler, an EntryPoint, and smart-account deployment. This proposal uses the public mempool; no bundler.
- **vs. Tempo access keys** — Tempo bakes a fixed access-key primitive into the tx envelope. This proposal keeps delegation as programmable caveats on top of existing frames, composable with 8141's PQ roadmap.
- **vs. D (base fork without permissions)** — D covers ~85% of the permissions UX via contract-layer work (session keys as scoped signers on 2D-nonce lanes, ERC-7710 on EOA default-code with `msg.sender = manager`). This proposal closes the remaining narrow case where `msg.sender = delegator` is required and cannot be worked around.

---

## 22. Spec delta summary

Against base EIP-8141 (assuming the base AA fork with 2D nonces + validity windows + guarantors has already shipped):

1. Include `execution-authority` EIP (standalone prerequisite).
2. Reserve a consensus-coordinated address for the canonical DelegationManager; pin address + code hash; immutable; upgrades via new reserved address at future forks.
3. Reserve `DELEGATION_MARKER` selector for default-code VERIFY calldata.
4. Add default-code delegation-redemption branch (§7). Calls `manager.isAuthorizedView`; on success calls `APPROVE(execution)`. No `APPROVE(payment)` in v1.
5. Default code MUST expose `validateAuth(bytes32 digest, bytes proof) returns (bool)` — account-agnostic, crypto-agnostic.
6. Add protocol affordance: `tx_context.sender_frames`.
7. Default code MUST invoke `manager.consumeAndFinalize` as post-op after successful SENDER frames. Atomic-revert semantics. 50 000 gas cap.
8. Adopt canonical caveat vocabulary (8 stateless types). Arbitrary caveat contracts are expansive-tier-only in v1.
9. Size caps: `MAX_PROOF_SIZE = 8192`, `MAX_CAVEAT_COUNT = 8`, `MAX_BUNDLE_SIZE = 16384`.
10. Canonical manager events (`DelegationRegistered`, `DelegationRedeemed`, `DelegationRevoked`) and entry points (`revoke`, `revokeAll`, `lookupDelegation`).
11. PQ migration: require non-zero `expiry` on every v1 delegation; domain separator carries scheme/version tag.
12. Mempool: restrictive tier for canonical-caveat / execution-only flows; expansive/private for shared-state caveats in v1.
13. VOPS profile for manager state (§16).
14. Adopt ERC-7715 verbatim for wallet RPC.

**Zero envelope changes. Zero new opcodes. Zero new precompiles. Zero new frame modes. Two default-code surface additions (delegation branch, `validateAuth` entrypoint). One canonical contract. Everything else is contract logic.**

Shipping timing: permissions is a **v2 fork**, after the base AA fork (with 2D nonces + validity windows + guarantors) has shipped and `execution_authority` is established. Bundling with the base fork is explicitly against coredev recommendation.

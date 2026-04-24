# Core Developer Feedback on 2D Nonces, Permissions, and Validity Windows

Perspective: Ethereum core developer reviewing whether these additions can be specified, implemented by clients, and carried through the post-quantum / FOCIL / VOPS roadmap without creating hidden consensus or policy debt.

## Executive assessment

The revised drafts materially address the main issues from the previous review. In particular:

- **2D nonces** now put `nonce_key` in the transaction envelope instead of a fake "APPROVE frame" or VERIFY calldata prefix. That fixes both prior correctness bugs: `APPROVE` is an opcode, not a frame, and VERIFY calldata is intentionally elided from `compute_sig_hash`.
- **2D nonces** keep the existing `tx.nonce` as the stream sequence. That removes the ambiguity around ignored or duplicated nonce fields.
- **2D nonces** now acknowledge that scalar nonce to nonce-map is a real state-model change, and add a consensus first-use surcharge for non-zero lanes. That is the right category of answer to the state-growth DoS concern.
- **Permissions** now introduce the missing `execution_authority` primitive instead of assuming SENDER frames can magically execute as the delegator. That is the most important semantic correction.
- **Permissions** now treat the DelegationManager as consensus-coordinated, split static validation from stateful settlement, restrict v1 to one-hop execution-only authorization, and stop relying on ERC-1271 as the protocol interface.
- **Validity windows** correctly move time bounds into the envelope instead of VERIFY logic, which is the only credible way to keep time-bounded transactions in the restrictive public mempool.

The direction is now coherent. The remaining issue is not "these drafts are impossible"; it is that they collectively expand EIP-8141 from a frame-transaction EIP into a bundle of account-model, transaction-envelope, mempool-policy, and system-contract changes. That may still be the right tradeoff, but it should be presented as a package with explicit fork scope, not as cheap add-ons.

My core-dev posture would be:

1. **Validity windows are the easiest to standardize.** They are envelope-only, deterministic, useful for PQ/encrypted-mempool flows, and low-risk for VOPS.
2. **2D nonces are feasible but need client-state design before they are ready.** The envelope shape is now right; the hard part is state representation, witnesses, sync, RPC, and lane-allocation accounting.
3. **Permissions are useful but not a minimal EIP-8141 dependency.** The revised design is much more honest, but it depends on `execution_authority`, a canonical manager, post-op semantics, and probably guarantors. That is a larger feature set than I would want on the critical path for the first native-AA fork.

## Check Against Previous Feedback

### 2D nonces

The prior review's main blockers were:

| Previous blocker | Current status |
|---|---|
| Claimed an "APPROVE frame" exists | **Fixed.** The proposal now uses an envelope field and does not rely on APPROVE-frame calldata. |
| Put nonce data in VERIFY calldata, which is elided from the sighash | **Fixed.** `nonce_key` is envelope-native and `tx.nonce` remains the sequence, so both are signed. |
| Left existing `tx.nonce` ambiguous | **Fixed.** `tx.nonce` is explicitly the stream sequence. |
| Treated scalar-to-map nonce state as a rename | **Partially fixed.** The draft now names account-object subtrie, witnesses, sync, and address derivation, but the exact trie encoding and client migration rules are still not specified. |
| Treated storage-growth DoS as mempool-only | **Fixed in category.** First-use lane allocation is now consensus-priced. The exact gas value and accounting still need specification. |
| Overloaded `eth_getTransactionCount` | **Fixed.** The draft now proposes `eth_getTransactionCountByKey`. |

This is a real improvement. The proposal is now in the right design family.

### Permissions

The prior review's main blockers were:

| Previous blocker | Current status |
|---|---|
| No way for SENDER frames to execute as an account other than `tx.sender` | **Fixed conceptually.** `execution_authority` is now an explicit tx-scoped variable. |
| Confused `tx.sender`, frame target, caller, and delegator | **Mostly fixed.** The examples now state `tx.sender = delegate`, `execution_authority = delegator`. |
| Relied on tx sighash coverage of delegation data in VERIFY calldata | **Fixed by separation.** Delegation data is authenticated by an independent delegation digest, while caveats inspect signed SENDER frames. |
| Used `STATICCALL` for replay consumption, events, quotas, and hooks | **Partially fixed.** Validation and settlement are split. v1 still needs a precise protocol hook for when `consumeAndFinalize` runs and what happens on SENDER-frame revert. |
| Called the manager a convention while default code calls it | **Fixed.** Manager address/code hash/immutability are now consensus-coordinated. |
| Overstated restrictive mempool compatibility | **Partially fixed.** v1 stateless caveats fit better; shared-state caveats are moved behind guarantors. The guarantor path is still speculative until that PR's shape is final. |

The permissions rewrite no longer has the obvious semantic hole. It is now implementable in principle, but it is no longer small.

## 2D Nonces

### Feasibility

The envelope shape is correct:

```text
[chain_id, nonce_key, nonce, sender, frames, fees...]
```

`nonce_key` selects the stream, `tx.nonce` remains the sequence, and consensus checks:

```text
tx.nonce == state[tx.sender].nonces[tx.nonce_key]
```

That is clean for signing, replacement, mempool readiness, and wallet mental models. It also aligns with the native clean-slate direction other proposals are converging on.

The difficult part is state. Ethereum clients currently treat account nonce as a scalar in the account object. Turning it into a sparse per-account map is not a local transaction-pool change. It affects:

- account trie encoding,
- witness shape,
- state sync and healing,
- pruning,
- database layout,
- RPC,
- empty-account semantics,
- transaction pool indexing,
- block execution accounting,
- consensus tests.

The draft recommends an account-object subtrie for non-zero lanes. That is a plausible answer, but it must be specified down to encoding before clients can evaluate complexity. A "subtrie rooted at the account" is not enough by itself; we need to know how it is committed, how it interacts with the existing account RLP fields, and whether this waits for a broader state-tree transition.

### VOPS / statelessness compatibility

2D nonces are VOPS-relevant because VOPS baseline currently assumes one nonce per account. A sparse lane map means a VOPS node validating transaction gossip must know `state[sender].nonces[nonce_key]` for arbitrary keys.

There are three possible strategies:

1. **Keep all live nonce lanes in the VOPS slice.** This is simple for validation but may grow without bound unless lane creation is capped or priced high enough.
2. **Keep only lane 0 in VOPS and require witnesses for non-zero lanes.** This preserves the baseline but makes every non-zero lane transaction carry witness data, which is bad for UX and mempool propagation.
3. **Bound public-mempool lanes per account and include active lanes in an AA-VOPS extension.** This is probably the practical middle: consensus prices lane creation; mempool policy caps active pending lanes; VOPS nodes track lane records that have been created.

The current draft gestures at option 3 but does not fully specify it. For FOCIL and VOPS, the key question is: can an attester validate a non-zero-lane tx using its validity slice without a full-state lookup? If the answer is "yes, active lane entries are part of VOPS", then the proposal needs a VOPS state-growth estimate. If the answer is "no, include a witness", then the restrictive-tier claim should be narrowed.

### FOCIL compatibility

Mempool readiness per `(sender, nonce_key, nonce)` is FOCIL-compatible as long as inclusion-list validators can cheaply check the lane state. It also improves inclusion-list quality: independent lanes avoid one stuck transaction blocking all activity from the same account.

The caveat is builder/attester complexity. FOCIL validation needs deterministic replacement and readiness rules across clients:

- exact RBF tuple: `(sender, nonce_key, nonce)`,
- exact pending cap semantics,
- exact treatment of future-valid transactions on the same lane,
- exact behavior if a transaction allocates a new lane,
- exact invalidation after a block increments any lane.

This is implementable, but it needs cross-client transaction-pool tests. 2D nonces are not just an execution-layer feature; they change mempool algorithms.

### Post-quantum roadmap compatibility

2D nonces are strongly aligned with the PQ roadmap. Ephemeral key rotation and one-time signer flows benefit from parallel streams because they reduce self-inflicted nonce contention. A wallet can reserve ranges for:

- normal user actions,
- ephemeral PQ signer rotation,
- recovery/admin actions,
- app/session flows,
- encrypted-mempool submissions.

However, 2D nonces do not themselves make accounts quantum-safe. They are a scheduling and replay primitive. The PQ benefit comes when account code or default code uses the stream key to constrain one-time keys and rotation policies.

### Recommendation

Keep the envelope-field design. Do not return to VERIFY-prefix encoding.

Before proposing this for fork inclusion, write a state appendix that answers:

1. Exact account encoding for non-zero lanes.
2. Exact witness format for a non-zero lane read/write.
3. Whether VOPS includes all created lanes, active lanes, or only lane 0.
4. Gas accounting for first lane creation and lane increment.
5. Whether non-zero lane state can ever be pruned.
6. Consensus behavior for lane overflow.
7. Cross-client txpool behavior for pending, queued, replacement, and eviction.

My likely call: feasible, valuable, but should only ship if the state representation is agreed early. If that cannot be settled in time, validity windows should not be blocked on it.

## Validity Windows

### Feasibility

Validity windows are the cleanest of the three proposals. Adding `valid_after` and `valid_before` as signed envelope fields gives clients an objective pre-frame check:

```text
if valid_after != 0:  block.timestamp > valid_after
if valid_before != 0: block.timestamp < valid_before
```

No opcode, no precompile, no default-code branch, no manager contract, no extra state. This is the kind of primitive the transaction envelope is good at.

The draft should tighten one encoding point: it says `valid_before == 0` is both "always expired" and "sentinel for no upper bound." Pick only one. I would define zero as no bound for both fields:

```text
valid_after = 0   means no lower bound
valid_before = 0  means no upper bound
```

Then a reverse finite window (`valid_before != 0 && valid_after >= valid_before`) is invalid by consensus.

### VOPS / FOCIL compatibility

Validity windows are VOPS-friendly. They require no state. They are FOCIL-friendly because inclusion-list validators can reject future or expired transactions from envelope data plus the slot timestamp.

The main policy work is txpool behavior:

- how long nodes store future-valid transactions,
- whether future-valid transactions are gossiped or only retained locally,
- whether a future-valid tx occupies its nonce position,
- how replacement works before the lower bound,
- how aggressively expired transactions are evicted.

Those are policy questions, not deep consensus blockers.

### Post-quantum roadmap compatibility

Validity windows help the PQ roadmap more than they may first appear. PQ migration involves larger signatures, possible aggregation, ephemeral keys, encrypted mempool flows, and time-sensitive reveal/order phases. Envelope-level validity lets nodes reason about these transactions without running validation code that reads `TIMESTAMP`, which would otherwise push them out of the restrictive tier.

For encrypted mempools, there is one nuance: if the transaction body is sealed, public nodes may not see these fields unless the envelope has an unencrypted admission wrapper. That is an EIP-8184-style design question, not a reason to avoid validity windows in EIP-8141.

### Recommendation

This is the best candidate for near-term inclusion. It is simple, improves UX, removes a known restrictive-mempool gap, and does not meaningfully worsen VOPS.

I would standardize validity windows independently even if 2D nonces and permissions are deferred.

## Permissions

### Feasibility

The revised permissions design is much stronger than the earlier draft because it admits the real primitive it needs:

```text
execution_authority: Optional[address]
```

That makes delegated execution semantically possible:

- `tx.sender` signs the transaction and consumes the tx-level nonce.
- a VERIFY frame targeting the delegator runs delegator/default code.
- if the manager authorizes the delegation, that code calls `APPROVE(execution)`.
- the protocol sets `execution_authority = delegator`.
- SENDER frames execute with `msg.sender = execution_authority`.

This is coherent. It also changes a core invariant of EIP-8141. Current spec says SENDER frames execute from `tx.sender`; the new rule says they execute from `execution_authority ?? tx.sender`. That affects access lists, gas estimation, tracing, wallet simulation, block builders, and security review.

The design also adds a canonical DelegationManager. If default code calls a reserved address and checks code hash, then the manager is part of the fork. That is acceptable only if the EIP owns that complexity directly:

- address assignment,
- bytecode,
- deployment at fork activation,
- immutability or fork-governed upgrades,
- chain-specific deployment histories,
- conformance tests,
- behavior if the manager call fails.

This starts to look like a system contract. Ethereum can do system contracts, but they require more discipline than "ecosystem convention."

### Restrictive mempool and guarantors

The MVP restriction to one-hop, stateless caveats, execution-only approval is the right starting point. Without guarantors, I would only consider restrictive-tier propagation for caveats that inspect signed SENDER-frame content and read no shared state.

The guarantor section is promising but should be treated as a dependency, not a solved property. If guarantors land, they can convert shared-state caveats from "mempool cannot safely simulate this" into "a guarantor underwrites the risk." That may make richer permissions publicly propagatable.

But if guarantors do not land, the permissions proposal should say plainly:

- stateless caveats can be restrictive-tier,
- shared-state caveats are expansive/private,
- stateful quotas and spend counters are v2 or expansive/private,
- manager-as-guarantor is unavailable.

The permission system should not depend on an unsettled guarantor design for its base correctness.

### VOPS compatibility

Permissions are VOPS-sensitive in two different ways.

First, delegated execution touches at least two accounts: `tx.sender` for nonce/payment validation and `execution_authority` for execution. That is fine during execution, but validation must remain bounded if the transaction is to propagate publicly and be FOCIL-enforceable.

Second, manager validation can easily read shared state:

- revocation registry,
- delegation nonce,
- caveat contracts,
- allowlists,
- ERC-20 balances,
- oracle contracts.

Those reads are outside the `tx.sender` VOPS slice unless the canonical manager and its bounded storage are explicitly added to the VOPS extension. The proposal should define a VOPS profile for v1:

```text
Restrictive permissions v1 may read:
- delegator account code/default code,
- canonical manager code,
- bounded manager storage for delegation nonce/revocation,
- signed SENDER-frame data from tx context,
- no arbitrary external caveat state unless a guarantor path is present.
```

If manager storage is part of the public validation path, VOPS nodes must carry it or receive witnesses. A global manager with large, hash-keyed revocation maps can become a VOPS pressure point similar to privacy-pool nullifier storage.

### FOCIL compatibility

FOCIL attesters need to validate inclusion-list transactions cheaply and deterministically. Permissions complicate that because invalidation can happen outside the sender's nonce:

- delegation revoked,
- delegation nonce consumed,
- manager upgraded in a later fork,
- caveat contract state changed,
- guarantor balance or commitment changed.

For v1, the proposal should specify invalidation rules. A transaction admitted at time T may become invalid before inclusion if the manager's revocation state changes. That is not unique to permissions, but it is more common here than for simple signature validation.

The safest FOCIL-compatible v1 is narrow:

- one-hop delegation,
- execution-only,
- no payment delegation,
- no re-delegation,
- no arbitrary caveat calls in restrictive tier,
- bounded manager storage reads,
- no stateful spend counters in validation,
- settlement only after successful execution.

Anything beyond that should be expansive-tier or guarantor-backed.

### Post-quantum roadmap compatibility

Permissions are conceptually aligned with the PQ roadmap because they avoid hardcoding ECDSA and use `validateAuth(digest, proof)` as a crypto-agnostic interface. That lets accounts authorize delegations with secp256k1 today, P256/passkeys, hybrid classical+PQ schemes, or pure PQ schemes later.

However, permissions also introduce a long-lived authorization surface. That matters for quantum safety:

- Delegation proofs signed with ECDSA or P256 remain quantum-vulnerable if they are valid far into the future.
- Delegation digests should include expiry and ideally scheme/domain metadata.
- Wallets should be able to revoke old classical delegations when migrating to PQ.
- The manager should not require ERC-1271 or `ecrecover` semantics.
- The manager interface must handle large PQ proofs without pushing common redemptions over validation gas caps.

For the PQ roadmap, the best property of this design is `validateAuth`. The riskiest property is persistent delegation state signed under pre-PQ keys. The spec should require explicit expiry and revocation support in v1, even if stateful spend limits are deferred.

### Recommendation

Do not put permissions on the same critical path as core EIP-8141 unless the fork scope explicitly includes:

1. `execution_authority`.
2. A consensus-coordinated immutable DelegationManager.
3. A tx-context surface for signed SENDER frames.
4. A post-op/finalization hook with revert semantics.
5. A restrictive-tier permissions profile.
6. A VOPS profile for manager state.
7. A clear answer on whether guarantors are included or future work.

My preferred sequencing:

1. Ship base EIP-8141 with validity windows if possible.
2. Ship 2D nonces once state encoding and VOPS treatment are settled.
3. Treat delegated permissions as a follow-on EIP built on `execution_authority`, unless there is strong agreement that native permissions are required for the same fork.

## Cross-Proposal Interactions

### Nonce ownership in delegated transactions

The current answer is correct: the tx-level nonce belongs to `tx.sender`, even if `execution_authority` is someone else. Delegation replay protection belongs to the manager, not to the delegator's protocol nonce.

That keeps the nonce model clean, but it means the manager's replay protection becomes consensus-adjacent for mempool validity. Clients need exact invalidation rules when manager state changes.

### Validity windows and 2D nonces

A future-valid transaction should reserve its sequence only on its own lane. It should not block other lanes. It should block later transactions on the same lane until included, replaced, dropped, or expired.

This needs transaction-pool tests because it combines three dimensions:

- lane readiness,
- future-valid deferral,
- replacement by fee.

### Validity windows and permissions

There are two time bounds:

- delegation expiry in the manager digest,
- transaction validity window in the envelope.

Both are useful and should remain separate. The envelope window bounds a specific redemption attempt. The delegation expiry bounds the underlying authority.

For PQ safety, wallets should prefer short transaction windows and short-lived classical delegations.

### Guarantors and 2D nonces

The "nonce advances on inclusion regardless of VERIFY outcome" rule is correct. Guarantors make that explicit: if a guaranteed tx is included and sender validation fails, gas is paid by the guarantor and the sender stream still advances.

This should be in the 2D nonce spec. Otherwise replay semantics around failed validation will be ambiguous.

## Compatibility With the Broader Roadmap

### Post-Quantum

- **Validity windows** are positive: they reduce the need for timestamp-reading validation code and help short-lived encrypted or ephemeral-key flows.
- **2D nonces** are positive: they support ephemeral signers, session streams, and recovery/admin isolation.
- **Permissions** are positive if `validateAuth` remains crypto-agnostic, but risky if long-lived ECDSA/P256 delegations become common.

None of the three directly solves PQ security. They support the migration path. The hard PQ work remains precompiles/opcodes, ephemeral key rotation, encrypted propagation, and ECDSA revocation.

### FOCIL

- **Validity windows** are easy for FOCIL.
- **2D nonces** are FOCIL-compatible if lane state is in the validity slice or witnessable cheaply.
- **Permissions** are FOCIL-compatible only for a narrow bounded-validation profile, or with a finalized guarantor mechanism.

The more permissions depend on shared manager/caveat state, the more they threaten the "attesters can cheaply validate inclusion lists" assumption.

### VOPS

- **Validity windows** add no state.
- **2D nonces** add account state; the proposal needs a VOPS accounting model.
- **Permissions** add validation state around manager storage and possibly caveat state; v1 must bound that or route through witnesses/guarantors/expansive tier.

For VOPS, 2D nonces are a state-growth question; permissions are a validation-state-dependency question.

### Expansive Mempool

The expansive tier should be treated as a release valve, not as proof that every feature is public-mempool-ready. A transaction being consensus-valid is not enough for FOCIL, censorship resistance, or wallet UX. Each proposal should label which flows are:

- restrictive/public/FOCIL-compatible,
- restrictive only with guarantor,
- expansive/private only,
- direct-to-builder only.

## Concrete Spec Questions Before Client Implementation

### 2D nonces

1. What is the exact account encoding for non-zero nonce lanes?
2. Are non-zero lanes part of the VOPS validity slice?
3. What witness is required to validate a non-zero lane?
4. What is `LANE_ALLOCATION_COST`, and does it differ before/after state-tree migration?
5. Can lanes be pruned or reclaimed?
6. What is the exact overflow behavior for `tx.nonce`?
7. What are txpool caps and RBF rules for multi-lane accounts?

### Validity windows

1. Is zero definitely "no bound" for both fields?
2. Are the bounds strict or inclusive? The draft uses `>` for `valid_after` and `<` for `valid_before`; the names should match that.
3. What is the max future deferral policy for public mempools?
4. Does a future-valid tx propagate or stay local until ready?
5. How does replacement work while future-valid?

### Permissions

1. Is `execution_authority` in the base EIP or a separate EIP?
2. Does `APPROVE(execution)` from any VERIFY target set `execution_authority = frame.target`?
3. What exactly is the DelegationManager bytecode and address?
4. What manager storage is allowed in restrictive validation?
5. How does `consumeAndFinalize` run, and what happens if SENDER execution reverts?
6. Are guarantors included in the same fork or not?
7. What is the maximum delegation bundle size?
8. What is the maximum caveat count?
9. Are caveat contracts allowed in restrictive tier, or only manager-native caveat types?
10. How are old classical delegations revoked during PQ migration?

## Bottom Line

The revisions did address the previous feedback on 2D nonces and permissions. The obvious correctness errors are gone.

From a core protocol perspective, I would separate the proposals by maturity:

- **Validity windows**: ready to pursue as a small envelope-level addition.
- **2D nonces**: feasible and valuable, but blocked on exact state representation and VOPS accounting.
- **Permissions**: semantically repaired, but large enough to deserve its own EIP or a clearly scoped sub-EIP. It should not be described as merely default-code behavior; it changes execution authority and introduces a system-contract-like manager.

If the goal is compatibility with the post-quantum roadmap, FOCIL, and VOPS, the priority should be primitives that keep validation cheap, signed data explicit, and state growth bounded. Validity windows satisfy that now. 2D nonces can satisfy it with a precise state design. Permissions can satisfy it only in a narrow v1 profile, with richer caveats deferred to guarantors or the expansive tier.

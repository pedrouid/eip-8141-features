# Core Developer Feedback on 2D Nonces, Permissions, and Validity Windows

Perspective: Ethereum core developer reviewing whether these additions can be specified, implemented by clients, and carried through the PQ / FOCIL / VOPS roadmap without creating hidden consensus or policy debt.

## Executive assessment

The revised drafts materially address the main issues from the previous review:

- **2D nonces** put `nonce_key` in the envelope instead of a fake "APPROVE frame" or VERIFY calldata prefix. Fixes both prior correctness bugs: `APPROVE` is an opcode, not a frame; VERIFY calldata is elided from `compute_sig_hash`.
- **2D nonces** keep the existing `tx.nonce` as the stream sequence, removing envelope-nonce ambiguity.
- **2D nonces** now acknowledge that scalar→map is a real state-model change, adding a consensus first-use surcharge for non-zero lanes.
- **Permissions** introduce the missing `execution_authority` primitive instead of assuming SENDER frames magically execute as the delegator.
- **Permissions** treat the DelegationManager as consensus-coordinated, split validation from settlement, restrict v1 to one-hop execution-only, and stop relying on ERC-1271.
- **Validity windows** correctly move time bounds into the envelope — the only credible way to keep time-bounded txs on the restrictive public mempool.

The direction is coherent. Remaining issue: these drafts collectively expand EIP-8141 from a frame-tx EIP into a bundle of account-model, envelope, mempool-policy, and system-contract changes. That may be the right tradeoff, but present it as a package with explicit fork scope, not cheap add-ons.

**My core-dev posture**:

1. **Validity windows are easiest to standardize.** Envelope-only, deterministic, useful for PQ / encrypted-mempool flows, low-risk for VOPS.
2. **2D nonces are feasible but need client-state design first.** Envelope shape is right; hard part is state representation, witnesses, sync, RPC, lane-allocation accounting.
3. **Permissions are useful but not a minimal 8141 dependency.** Semantically repaired but depends on `execution_authority`, a canonical manager, post-op semantics, and probably guarantors — too large for the critical path for the first native-AA fork.

## 2D Nonces

### Feasibility

Envelope shape is correct. Consensus check `tx.nonce == state[tx.sender].nonces[tx.nonce_key]` is clean for signing, replacement, mempool readiness, wallet models.

The hard part is state. Clients treat account nonce as a scalar. A sparse per-account map affects trie encoding, witness shape, state sync, pruning, database layout, RPC, empty-account semantics, txpool indexing, execution accounting, consensus tests.

Draft recommends an account-object subtrie. Plausible, but must be specified down to encoding — how committed, how it interacts with existing account RLP fields, whether this waits for a broader state-tree transition.

### VOPS compatibility

Three strategies: all lanes in VOPS slice (unbounded without caps); only lane 0 in VOPS + witnesses for non-zero (bad for UX); bound public-mempool lanes + AA-VOPS extension (practical middle). Draft gestures at option 3 but doesn't fully specify. Key question: can an attester validate without a full-state lookup?

### FOCIL compatibility

Per-lane readiness is FOCIL-compatible if IL validators can cheaply check lane state. Independent lanes improve IL quality. Needs deterministic cross-client rules (RBF tuple, pending-cap, future-valid treatment, lane-allocation, block-invalidation) — implementable but needs cross-client txpool tests.

### PQ compatibility

Aligned with roadmap. Parallel streams support ephemeral key rotation, one-time signer flows, session streams, recovery/admin isolation. 2D nonces don't make accounts quantum-safe; they're scheduling/replay primitives.

### Recommendation

Keep envelope-field design. Before fork proposal, write a state appendix: exact account encoding; witness format; VOPS coverage; gas accounting for creation/increment; pruning; overflow; cross-client txpool behavior. Ship only if state representation is agreed early. Validity windows should not be blocked on it.

## Validity Windows

### Feasibility

Cleanest of the three. Adding `valid_after` / `valid_before` as signed envelope fields gives clients an objective pre-frame check. No opcode, precompile, default-code branch, manager contract, extra state.

Tighten one point: draft says `valid_before == 0` is both "always expired" and "no upper bound." Pick one. Define zero as no-bound for both; a reverse finite window (`valid_before != 0 && valid_after >= valid_before`) is consensus-invalid.

### VOPS / FOCIL compatibility

VOPS-friendly (no state). FOCIL-friendly — IL validators can reject future/expired txs from envelope data plus slot timestamp.

Main policy work is txpool behavior: deferral horizon, gossip, nonce position reservation, replacement before lower bound, expiry eviction. Policy, not consensus blockers.

### PQ compatibility

Positive: envelope-level validity lets nodes reason about PQ/ephemeral flows without running validation code reading `TIMESTAMP`. Encrypted-mempool nuance: sealed tx bodies may need an unencrypted admission wrapper — EIP-8184-style design question, not a reason to avoid validity windows in 8141.

### Recommendation

Best near-term inclusion candidate. Simple, improves UX, removes a known restrictive-mempool gap, doesn't worsen VOPS. Standardize independently even if 2D nonces and permissions are deferred.

## Permissions

### Feasibility

Revised design is much stronger because it admits the real primitive: `execution_authority: Optional[address]`. `tx.sender` signs + consumes tx nonce; a VERIFY frame targeting the delegator runs delegator code; if the manager authorizes, that code calls `APPROVE(execution)`; protocol sets `execution_authority = delegator`; SENDER frames execute with `msg.sender = execution_authority`.

Coherent — but also changes a core invariant. Current spec: SENDER executes from `tx.sender`. New rule: executes from `execution_authority ?? tx.sender`. Affects access lists, gas estimation, tracing, wallet simulation, block builders, security review.

Canonical DelegationManager. If default code calls a reserved address and checks code hash, the manager is part of the fork. Acceptable only if the EIP owns that complexity: address assignment, bytecode, deployment at activation, immutability or upgrade rules, conformance tests, behavior if the manager call fails. Starts to look like a system contract — Ethereum can do system contracts, but they require discipline beyond "ecosystem convention."

### Restrictive mempool and guarantors

v1 restriction to one-hop, stateless caveats, execution-only is the right start. Without guarantors, restrictive-tier propagation only for caveats that inspect signed SENDER-frame content and read no shared state.

Guarantor section is promising but should be a dependency, not a solved property. If guarantors land, shared-state caveats become "underwritten" rather than "mempool can't simulate." If not, the permissions proposal should say plainly: stateless caveats restrictive-tier; shared-state caveats expansive/private; stateful quotas v2/private; manager-as-guarantor unavailable.

### VOPS compatibility

Two axes. First: delegated execution touches at least two accounts (`tx.sender` for nonce/payment, `execution_authority` for execution). Fine during execution; validation must remain bounded for public propagation + FOCIL enforceability.

Second: manager validation can easily read shared state (revocation, delegation nonce, caveat contracts, allowlists, ERC-20 balances, oracles). Outside the `tx.sender` VOPS slice unless the canonical manager and its bounded storage are explicitly added to a VOPS extension. Proposal should define a v1 VOPS profile: delegator code, manager code, bounded manager storage for delegation nonce/revocation, signed SENDER-frame data, no arbitrary external caveat state unless guarantor-backed.

A global manager with large hash-keyed revocation maps can become a VOPS pressure point similar to privacy-pool nullifier storage.

### FOCIL compatibility

Permissions complicate FOCIL because invalidation can happen outside the sender's nonce: delegation revoked; delegation nonce consumed; manager upgraded; caveat state changed; guarantor balance/commitment changed. For v1, specify invalidation rules.

Safest v1: one-hop, execution-only, no payment delegation, no re-delegation, no arbitrary caveat calls in restrictive tier, bounded manager storage reads, no stateful spend counters in validation, settlement only after successful execution. Anything beyond → expansive-tier or guarantor-backed.

### PQ compatibility

Conceptually aligned because `validateAuth(digest, proof)` is crypto-agnostic.

Risk: long-lived authorization surface. ECDSA/P256-signed delegations remain quantum-vulnerable if valid far into the future. Delegation digests need expiry and scheme/domain metadata; wallets must revoke old classical delegations during PQ migration; manager shouldn't require `ecrecover` semantics; interface must handle large PQ proofs.

v1 should require explicit expiry and revocation even if stateful spend limits are deferred.

### Recommendation

Do not put permissions on the critical path for core EIP-8141 unless the fork scope explicitly includes all of: `execution_authority`; a consensus-coordinated immutable DelegationManager; a tx-context surface for signed SENDER frames; a post-op/finalization hook with revert semantics; a restrictive-tier permissions profile; a VOPS profile for manager state; a clear answer on whether guarantors are included or future work.

Preferred sequencing:
1. Ship base EIP-8141 with validity windows if possible.
2. Ship 2D nonces once state encoding and VOPS treatment are settled.
3. Treat delegated permissions as a follow-on EIP built on `execution_authority` unless strong agreement emerges that native permissions are required for the same fork.

## Cross-proposal interactions

### Nonce ownership in delegated txs

Correct as currently designed: tx-level nonce belongs to `tx.sender` even if `execution_authority` is someone else. Delegation replay belongs to the manager, not to the delegator's protocol nonce. Clean nonce model — but manager's replay protection becomes consensus-adjacent for mempool validity. Clients need exact invalidation rules on manager-state changes.

### Validity windows and 2D nonces

Future-valid tx should reserve its sequence only on its own lane; not block other lanes; block later txs on the same lane until included, replaced, dropped, or expired. Combines three dimensions — lane readiness, future-valid deferral, RBF — needs cross-client tests.

### Validity windows and permissions

Two time bounds: delegation expiry in the manager digest; tx validity window in the envelope. Both useful, keep separate. Envelope window bounds a specific redemption; delegation expiry bounds the underlying authority. For PQ safety, wallets should prefer short tx windows and short-lived classical delegations.

### Guarantors and 2D nonces

The "nonce advances on inclusion regardless of VERIFY outcome" rule is correct. Guarantors make it explicit: included + sender validation fails + guarantor pays → stream still advances. Should be in the 2D-nonce spec, otherwise replay semantics around failed validation will be ambiguous.

## Compatibility with the broader roadmap

### PQ

- Validity windows positive: reduce need for timestamp-reading validation code, help short-lived encrypted/ephemeral flows.
- 2D nonces positive: support ephemeral signers, session streams, recovery/admin isolation.
- Permissions positive if `validateAuth` stays crypto-agnostic; risky if long-lived ECDSA/P256 delegations become common.

None directly solve PQ security. They support the migration path.

### FOCIL

- Validity windows easy.
- 2D nonces compatible if lane state is in the validity slice or witnessable cheaply.
- Permissions compatible only for a narrow bounded-validation profile or with a finalized guarantor mechanism.

### VOPS

- Validity windows add no state.
- 2D nonces add account state; need a VOPS accounting model.
- Permissions add validation state around manager storage and possibly caveat state; v1 must bound or route through witnesses / guarantors / expansive tier.

### Expansive mempool

Treat as a release valve, not as proof that every feature is public-mempool-ready. Consensus validity ≠ FOCIL / censorship-resistance / wallet UX. Each proposal should label which flows are restrictive/public/FOCIL-compatible, restrictive with guarantor, expansive/private, direct-to-builder only.

## Concrete spec questions before client implementation

### 2D nonces
1. Exact account encoding for non-zero lanes?
2. Are non-zero lanes part of the VOPS validity slice?
3. Witness required for a non-zero lane?
4. `LANE_ALLOCATION_COST`? Does it differ before/after state-tree migration?
5. Can lanes be pruned?
6. `tx.nonce` overflow behavior?
7. Txpool caps and RBF rules for multi-lane accounts?

### Validity windows
1. Is zero definitely "no bound" for both fields?
2. Strict or inclusive bounds?
3. Max future deferral policy?
4. Does a future-valid tx propagate or stay local until ready?
5. Replacement while future-valid?

### Permissions
1. `execution_authority` in base EIP or separate EIP?
2. Does `APPROVE(execution)` from any VERIFY target set `execution_authority = frame.target`?
3. DelegationManager bytecode and address?
4. Manager storage allowed in restrictive validation?
5. How does `consumeAndFinalize` run, and what happens if SENDER reverts?
6. Guarantors in the same fork or not?
7. Max delegation bundle size?
8. Max caveat count?
9. Caveat contracts allowed in restrictive tier or only manager-native types?
10. How are old classical delegations revoked during PQ migration?

## Bottom line

Revisions addressed previous feedback. Separate by maturity:

- **Validity windows**: ready as a small envelope-level addition.
- **2D nonces**: feasible and valuable; blocked on state representation and VOPS accounting.
- **Permissions**: semantically repaired but deserves its own EIP or clearly scoped sub-EIP. Not "merely default-code behavior" — changes execution authority, introduces a system-contract-like manager.

Priority for PQ/FOCIL/VOPS: primitives that keep validation cheap, signed data explicit, state growth bounded. Validity windows satisfy now. 2D nonces can with precise state design. Permissions only in a narrow v1 profile.

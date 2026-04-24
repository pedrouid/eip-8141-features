# Evaluation — Fork Scope Scenarios for EIP-8141

_Author: Claude. Scratch doc, not indexed on the site. Evaluates five candidate fork-scope combinations and recommends the best compromise for landing EIP-8141 successfully._

Scenarios:

- **A**: guarantor only
- **B**: guarantor + 2D nonces
- **C**: guarantor + validity windows
- **D**: guarantor + 2D nonces + validity windows
- **E**: guarantor + 2D nonces + validity windows + permissions

Each scenario assumes the base EIP-8141 (frame transactions, default code, APPROVE opcode, existing VERIFY/SENDER frame semantics) is already in the same fork. The scenarios differ only in which additional features ride with it.

**Weighting.** Core-dev feedback is weighted more heavily than wallet-dev feedback because core devs are the ones who implement, test, and carry the consensus risk. A scenario that wallet devs love but core devs push back on does not ship. A scenario that core devs approve but wallet devs can layer on top of ships and then gets extended by the application layer. Every scenario below therefore also evaluates:

- **Today's production wallet stack** — what wallet devs already build against (ERC-4337, ERC-7710, bundlers, paymasters, offchain session infrastructure).
- **Layering without waiting for the next fork** — what the wallet + contract layer can deliver on top of this scenario without requiring further consensus work.

This second lens is critical because the biggest compromise lever is: **every feature that can be moved to the contract or wallet layer shrinks the fork**, and many features once thought to require protocol changes can be provided by the existing ERC-4337/7710 ecosystem with modest adaptation.

---

## Scenario A — Guarantor only

### Changes

| Surface | Addition |
| --- | --- |
| Envelope fields | none |
| Canonical contracts | none |
| Pre-tx checks | gas-payment resolution (sender VERIFY success → payer; failure → guarantor) |
| Tx-scoped state | `guarantor: Optional[address]` |
| APPROVE scopes | new `APPROVE(guarantee)` |
| Default code | unchanged |
| Mempool | sender-VERIFY simulation skippable when guarantor commitment present; shared-state reads in sender VERIFY admissible under guarantor backing |
| RPC | none |

### Core-dev perspective (weighted heavier)

Smallest possible addition beyond base EIP-8141. One APPROVE scope, one tx-scoped field, one mempool-tier rule. No new system contract, no envelope changes, no state-trie impact.

Main review surface: the mempool relaxation. Guarantors route shared-state-read risk from a mempool-policy violation into an economic-risk problem the guarantor absorbs. VOPS invariant is preserved (guarantor commitment is inside every node's slice) but nodes must reason about the guarantor's balance and commitment during admission.

PR #11555 is still early. Core-dev review would be on familiar ground (mempool/admission, not consensus paradigm) but wants convergence on the exact gas-payment resolution and VOPS profile before merge.

**Core-dev risk profile: low.** Scope creep is minimal.

### Wallet-dev perspective

Limited direct wallet value. Guarantors alone are an **infrastructure-layer** feature:

- ERC-20 gas paymasters with trustless onchain verification on the public mempool.
- Privacy flows (nullifier reads).
- Complex AA validation flows.

They do not solve nonce blocking, stale signatures, session keys, or delegated recovery.

### Today's production wallet stack

- ERC-4337 UserOperations via bundlers, EntryPoint singleton.
- Offchain paymasters (Pimlico, Biconomy, Stackup, Alchemy, etc.) for sponsored txs.
- ERC-7710 delegation for MetaMask Smart Accounts (smart contract wallets only).
- ERC-7715 wallet RPC for permission requests.
- Per-account offchain session-key infrastructure.
- EOA users: bare signed txs, stuck-nonce problem, no time bounds, no delegation.

### Layering without waiting for the next fork

What the wallet + contract layer can deliver on top of A:

- **ERC-20 paymasters propagate publicly** without bundlers. Measurable infrastructure win for non-smart-wallet users who rely on sponsored gas.
- Still rely on ERC-4337 for smart-account UX.
- Still rely on ERC-7710 (smart-account-only) for delegation.
- Nonce blocking and stale-signature problems persist for EOAs.

Wallet gap-bridging amounts to "adopt native paymasters when available, keep the ERC-4337 stack for everything else." Minimal investment, minimal payoff.

Verdict: A ships easily but leaves users with essentially the same UX they have today. The fork justifies effort only if the user delta is more substantial.

---

## Scenario B — Guarantor + 2D Nonces

### Changes

| Surface | Addition |
| --- | --- |
| Envelope fields | `nonce_key: uint256` |
| Canonical contracts | `NonceLaneRegistry` (reserved address, immutable, EIP-4788 pattern) |
| Pre-tx checks | nonce-lane check (system-call to registry for `nonce_key > 0`); gas-payment resolution (guarantor) |
| Tx-scoped state | `guarantor` |
| APPROVE scopes | `APPROVE(guarantee)` |
| Default code | `tx.nonce_key` added to tx-context surface |
| Mempool | per-lane readiness, per-lane RBF, `MAX_ACTIVE_STREAMS_PER_SENDER` cap, guarantor tier-relaxation |
| RPC | `eth_getTransactionCountByKey`, new error codes |

### Core-dev perspective (weighted heavier)

Two independent changes, both with clear precedent. `NonceLaneRegistry` follows the twice-accepted EIP-4788 / EIP-2935 pattern — no new consensus paradigm. Pre-tx system-call hook for non-zero keys extends existing machinery.

State-growth impact bounded: SSTORE-from-zero (20 000 gas) inside the registry prices lane allocation; mempool caps active pending streams. VOPS state-growth budget ~2 GB/year legitimate, ~1 GB/day adversarial. Comparable to other state-growing features on the roadmap.

FOCIL must handle per-lane RBF semantics and block-invalidation rules. Implementable, but requires cross-client transaction-pool tests — this is the main new engineering surface beyond the registry contract itself.

**Core-dev risk profile: moderate.** The registry-contract pivot eliminated the largest objection. Cross-client mempool tests become the critical path.

### Wallet-dev perspective

The **wallet UX breakthrough scenario** for the nonce-blocking problem:

- Stuck swap no longer blocks recovery actions.
- Game session no longer blocks ordinary account activity.
- Scheduled tx doesn't freeze future activity.
- Dapp session concurrency without wallet-side serialization.

Wallet work bounded: lane-selection strategy, RPC integration, hardware-wallet lane display, lane-namespace conventions.

Still missing: stale-signature protection, session-key UX.

### Today's production wallet stack

- ERC-4337 2D nonces via bundlers: 192-bit key + 64-bit seq packed into a `uint256`, only for smart accounts with EntryPoint. Wallets like Coinbase Smart Wallet already use this.
- EOAs: no 2D nonces. Wallets paper over by juggling multiple EOA addresses for different purposes, or serializing actions.

### Layering without waiting for the next fork

What wallet + contract layer can deliver on top of B:

- **Native 2D nonces universally**, for every EOA, day one. Wallets no longer need smart-account deployment for concurrent pending txs.
- **Validity windows via VERIFY-frame `block.timestamp` checks** still work — just not in the restrictive tier. Wallets wanting time-bounded txs route them through expansive/private tiers or direct-to-builder. Worse propagation, same correctness. Acceptable for dapp-specific flows (swaps via MEV-aware private relays already), not acceptable for general wallet UX.
- **Session keys via 2D-nonce lanes** — a wallet can dedicate a lane to each dapp and sign redemption txs from the user's own account with a wallet-held session key that's authorized only for specific lanes via custom default-code logic. This is a real contract-layer pattern: it gives session-key-like UX without needing `execution_authority`, because `tx.sender` stays the user and the session key is a scoped signer on the user's account.
- **ERC-4337 + 7710 stack continues** for delegated-execution flows where `msg.sender` must differ from the submitter.

B gives wallets the single biggest UX win missing today, plus lane isolation that enables session-like UX without delegated-execution primitives. Good but incomplete.

---

## Scenario C — Guarantor + Validity Windows

### Changes

| Surface | Addition |
| --- | --- |
| Envelope fields | `valid_after: uint64`, `valid_before: uint64` |
| Canonical contracts | none |
| Pre-tx checks | time-window check (`block.timestamp` vs bounds); gas-payment resolution (guarantor) |
| Tx-scoped state | `guarantor` |
| APPROVE scopes | `APPROVE(guarantee)` |
| Default code | unchanged |
| Mempool | future-valid deferral (tiered: 1 h public / 24 h expansive / unlimited direct), `GOSSIP_THRESHOLD = 60 s`, expiry eviction |
| RPC | new error codes (`validity_window_too_far_future`, etc.) |

### Core-dev perspective (weighted heavier)

Validity windows are the cleanest of the additions. Envelope-only, no state, no system contracts, no new witness format. Pre-tx check is a comparison against `block.timestamp` — deterministic, cheap, FOCIL-friendly. VOPS impact: zero. Review work is mempool policy, not consensus.

Coredev feedback explicitly named validity windows as "the easiest to standardize."

**Core-dev risk profile: very low.** Could ship ahead of the others in a dedicated small EIP if fork-scope pressure mounts.

### Wallet-dev perspective

The **most user-safety-positive** of the additions:

- Swaps expire automatically.
- Limit orders die at their deadline.
- Auction bids invalidate after the phase closes.
- Scheduled payments activate at their time.
- Mobile-wallet flows survive intermittent connectivity without stale-broadcast risk.

Easy to surface: "valid for 2 minutes," local-time labels, warnings on long windows. Hardware wallets parse two extra fields.

Still missing: nonce blocking, session-key UX.

### Today's production wallet stack

- ERC-4337 `validUntil` / `validAfter` fields in UserOperation, enforced by bundler and EntryPoint.
- Smart-account wallets already surface bounded validity in signing prompts.
- EOAs: dapp-side calldata tricks (e.g., Uniswap deadline inside the swap call), no protocol-level expiry.
- Relayers: enforce window clauses via their own submission logic (off-chain).

### Layering without waiting for the next fork

What wallet + contract layer can deliver on top of C:

- **Universal native expiry**, day one, for every account type. ERC-4337's `validUntil`/`validAfter` can map to the envelope fields as a wallet-side adapter; bundlers can stop enforcing them separately.
- **Short-lived delegations become safer** — even without permissions in this fork, session-key patterns implemented via ERC-4337 or custom default-code can now bound the redemption window at the envelope level rather than in the delegation bundle alone. Defense in depth for PQ migration.
- **Nonce blocking persists** for EOAs. Wallets still serialize actions or juggle multiple addresses. Session-key UX still flows through the existing ERC-4337 / 7710 stack.
- **Stale-signature attack surface closed** for the common case (swaps, auctions, scheduled payments). Measurable user-safety win.

Good safety floor, less UX ceiling than B.

---

## Scenario D — Guarantor + 2D Nonces + Validity Windows

### Changes

| Surface | Addition |
| --- | --- |
| Envelope fields | `nonce_key: uint256`, `valid_after: uint64`, `valid_before: uint64` (3 total) |
| Canonical contracts | `NonceLaneRegistry` |
| Pre-tx checks | time-window check; nonce-lane check (system-call); gas-payment resolution |
| Tx-scoped state | `guarantor` |
| APPROVE scopes | `APPROVE(guarantee)` |
| Default code | `tx.nonce_key` in tx-context surface |
| Mempool | per-lane readiness, future-valid deferral, combined RBF, guarantor tier-relaxation |
| RPC | `eth_getTransactionCountByKey` + validity-window error codes |

### Core-dev perspective (weighted heavier)

Three independent features, each reviewed on its own merits:

- Validity windows: minimal, high-confidence, ships easily.
- 2D nonces: bounded complexity via registry-contract design; requires cross-client mempool tests.
- Guarantors: small consensus footprint; PR #11555 converges in parallel.

Three are largely orthogonal. Validity windows add zero VOPS pressure. 2D nonces add bounded state growth in the registry. Guarantors shift mempool-admission economics without adding state.

Cross-proposal interactions needing cross-client tests: future-valid tx reserving sequence on its lane; RBF across `(sender, nonce_key, tx.nonce)` while future-valid; stream-advances-on-inclusion under sender-VERIFY failure (when guarantor pays). All implementable; all have pinned decisions in `research.md`.

**Core-dev risk profile: moderate.** Every piece has independent design precedent. The registry-contract pivot for 2D nonces is the piece most likely to stretch timelines; validity windows provide a clean fallback if 2D nonces slip.

**Resilience property**: any one of the three can be pulled from the fork if it slips during review, without invalidating the other two.

### Wallet-dev perspective

The **"complete UX package"** for EOAs without delegated permissions:

- No stuck txs, no stale signatures, paymaster UX with shared-state reads, scheduled/future-valid txs on their own lanes, hardware-wallet-friendly.

Wallet work is substantial but well-scoped: RPC integration, nonce-lane-strategy conventions, validity-window display, hardware-wallet field parsing. All incremental additions to existing paths.

Still missing: session keys / delegated execution (permissions). This is the remaining big UX gap — but it can be substantially layered on top of D without a further fork, as described below.

### Today's production wallet stack

Same as C's description, plus: ERC-4337 2D nonces via bundlers (smart-account-only), offchain session-key management for smart accounts, MetaMask Smart Accounts Kit for ERC-7710 delegations, Rhinestone / Safe / Biconomy modular smart-account frameworks.

### Layering without waiting for the next fork

This is where D's value compounds beyond the sum of its parts. With all three features available, a lot of what looked like "needs permissions" becomes achievable in contracts + wallet code:

1. **Session keys via 2D-nonce lanes + validity-window expiry.** User's wallet dedicates a lane to each dapp. A session key is a scoped signer on the user's own account, allowed by custom default-code to sign txs only for that dapp's lane, within a validity window. `tx.sender` remains the user; the session key never becomes a separate account. Dapp-side UX is identical to ERC-7710 session keys for the common case.
2. **Short-term delegations** where the delegator pre-signs a tx with tight validity windows; delegate submits via relayer. Works today, much cleaner with C's envelope fields protecting against stale redemption.
3. **Recovery / admin flows on reserved lanes.** An "admin lane" on a reserved `nonce_key` accepts signatures from guardian devices; the wallet enforces this in custom default code. Caveats are contract-authored and wallet-verified before signing, same pattern as ERC-7710 caveats, but evaluated pre-sign rather than post-sign.
4. **Scheduled transactions** via `valid_after` become a native primitive. No contract-side automation needed for simple time-triggered flows.
5. **Stateless ERC-7710 on EOA default-code.** A DelegationManager contract can be deployed without consensus changes: delegate submits a tx (as tx.sender = delegate), calls `DelegationManager.redeemDelegation(bundle, actions)`. Manager verifies the offchain delegation signature, runs caveats, then CALLs targets. For ERC-20 transfers and target-allowlisted flows this works because `msg.sender = manager` suffices when the delegator has pre-approved the manager to act. This is exactly how today's ERC-7710 works for smart-account wallets — it generalizes to D's EOAs once they have default-code that accepts manager-routed calls.
6. **Guarantor-backed shared-state caveats** propagate through the public mempool once PR #11555's guarantor lands. Caveats reading ERC-20 balances or oracle contracts become restrictive-tier-admissible under guarantor backing.

What **still** requires execution_authority (and therefore a later fork):

- Delegated flows where `msg.sender` must literally be the delegator inside the SENDER frame — e.g., calling a contract that does `require(msg.sender == owner)` without prior approval pre-configuration. This is the narrow case ERC-4337 / ERC-7710 already handle by putting the user inside a smart account.
- For everything else, D + contract-layer ERC-7710 covers the UX.

**This is the pivotal argument for D as the best compromise**: it enables roughly 80-90 % of the delegated-permissions UX via contract-layer work, deferring only the narrow `msg.sender = delegator` case to a later fork. Wallets don't have to wait another year for session keys to ship; they ship session keys in software on top of D's primitives.

---

## Scenario E — Guarantor + 2D Nonces + Validity Windows + Permissions

### Changes

| Surface | Addition |
| --- | --- |
| Envelope fields | `nonce_key`, `valid_after`, `valid_before` (3 total; permissions adds none) |
| Canonical contracts | `NonceLaneRegistry`, `DelegationManager` (2 total, both immutable, reserved addresses) |
| Pre-tx checks | time-window check; nonce-lane check; gas-payment resolution |
| Tx-scoped state | `guarantor`, `execution_authority` |
| APPROVE scopes | `APPROVE(guarantee)`; generalized `APPROVE(execution)` (sets `execution_authority = VERIFY target`) |
| Execution rule change | SENDER frames run with `msg.sender = execution_authority ?? tx.sender` |
| Default code | `validateAuth(digest, proof)` entrypoint; delegation-redemption branch; post-op invocation of `manager.consumeAndFinalize`; `tx.nonce_key` and `tx_context.sender_frames` surfaces |
| Caveats | canonical vocabulary of 8 caveat types for restrictive tier |
| Mempool | all of D's changes + restrictive-tier profile for permissions |
| RPC | `eth_getTransactionCountByKey` + validity-window error codes + ERC-7715 (`wallet_grantPermissions`) |

### Core-dev perspective (weighted heavier)

Large fork scope. Two system contracts, two tx-scoped state variables, a core-invariant change (SENDER `msg.sender` rule), multiple default-code interface requirements, canonical caveat vocabulary register.

Specific concerns:

- **SENDER-frame `msg.sender` rule change** is a core invariant — every client touches it, every tool re-audits it.
- `execution-authority` EIP must ship in the same fork.
- DelegationManager VOPS profile adds validation-state dependency.
- Default-code surface doubles.
- PQ migration complexity for long-lived classical-signed delegations.

Coredev feedback was direct: "Do not put permissions on the same critical path as core EIP-8141 unless the fork scope explicitly includes [8 prerequisite items]."

**Core-dev risk profile: high.** Each feature is implementable individually; bundling multiplies review surface, test surface, and timeline risk.

### Wallet-dev perspective

The **"everything users hoped smart wallets would deliver, now on EOAs"** scenario: session keys, delegated game actions, scheduled automation, dapp-scoped allowances, recovery lanes, passkey-secured daily limits.

Wallet work is large: permission prompts displaying roles separately, revocation UI with event-indexing + local cache, canonical caveat rendering for hardware wallets, PQ migration workflows, SDK schemas for every new primitive.

Walletdev feedback was wary: user safety depends on strong display + revocation infrastructure, and v1 must be narrow (one-hop, stateless caveats, execution-only, canonical vocabulary). Anything looser and safety deteriorates faster than the UX win lands.

### Today's production wallet stack

Same as D plus: ERC-7710 / ERC-7715 reference implementation via MetaMask, deployed DelegationManager contracts, real session-key flows in MetaMask Smart Accounts Kit (smart-account users), typed-permission schemas for common caveats.

### Layering without waiting for the next fork

E is the last-mile closing the delegated-execution gap that D cannot close. But the wallet work already has an answer in D: layer ERC-7710 on top of D's primitives via a deployed DelegationManager contract and custom default-code extensions, accepting the `msg.sender = manager` limitation for v1.

Given that the wallet layer can deliver ~80-90 % of E's UX via D + contract-layer work, the incremental value of E over D is the narrow set of delegated flows where `msg.sender = delegator` is required and cannot be worked around via contract pre-approval.

For that narrow delta, E demands:
- A core-invariant change (SENDER `msg.sender` rule).
- A second canonical contract.
- Four default-code interface requirements.
- Multiple new mempool rules and VOPS profiles.
- Full PQ migration story in v1.

The ratio of review burden to incremental user-visible win is worst in E.

---

## Summary comparison

| | A | B | C | D | E |
| --- | --- | --- | --- | --- | --- |
| New envelope fields | 0 | 1 | 2 | **3** | 3 |
| New canonical contracts | 0 | 1 | 0 | 1 | **2** |
| New tx-scoped state | 1 | 1 | 1 | 1 | 2 |
| Core-invariant changes | 0 | 0 | 0 | 0 | **1** |
| Default-code interface additions | 0 | 1 | 0 | 1 | **4** |
| Mempool policy additions | 1 | 2 | 2 | 3 | 3 |
| Core-dev review burden | low | moderate | very low | moderate | high |
| Wallet-side work | minimal | moderate | small | moderate | large |
| Fraction of permissions UX available via contract-layer on top | ~30 % | ~50 % | ~40 % | **~85 %** | 100 % |
| Timeline risk | low | moderate | very low | moderate | high |

---

## Conclusion — best compromise

**Scenario D (guarantor + 2D nonces + validity windows) is the best compromise.**

Core-dev feedback weighted most heavily leads the conclusion: D is the largest fork that every core-dev-reviewed item has a path to. Validity windows ship cleanly. 2D nonces post the registry-contract pivot avoid account-encoding changes and reuse the EIP-4788 / EIP-2935 precedent. Guarantors are a bounded mempool-admission rule. None introduce a core-invariant change. None require two system contracts in the same fork. Each can be pulled from the fork independently without invalidating the others.

Wallet-dev feedback confirms the same ranking: D delivers the concrete UX wins users complain about most (nonce blocking + stale signatures + paymaster coverage). The single gap D leaves — full delegated execution where `msg.sender = delegator` — is narrow enough that the wallet + contract layer can cover ~85 % of it without a new fork.

### The permissions deferral argument (the core lever)

D lets permissions ship as software:

- **Session keys** → scoped signers on the user's own account, enforced by custom default-code, isolated on 2D-nonce lanes, bounded by validity windows. `tx.sender` stays the user.
- **Dapp allowances** → ERC-7710-style DelegationManager contracts deployed at application layer; `msg.sender = manager` for ERC-20 flows where delegator pre-approves the manager (same as today's ERC-7710 pattern, extended to EOAs).
- **Scheduled payments** → native via `valid_after` envelope field.
- **Recovery / admin flows** → reserved nonce lanes + guardian signatures in custom default-code.
- **Guarantor-backed rich caveats** → shared-state reads propagate publicly once PR #11555 lands.

This means the ecosystem does **not need a hard fork this year** for session-key UX. The contracts and wallet code can ship on top of D's primitives while the `execution_authority` / full-permissions EIP iterates through its own review cycle.

### Why not A, B, or C

- **A** ships easily but leaves users with essentially the same UX. The fork justifies AA-level review effort only if the user delta is more substantial.
- **B** delivers the biggest single UX win (nonce blocking) but omits validity windows — the cheapest and safest feature, with zero state impact and zero system contracts. Hard to justify leaving out.
- **C** is the safest and simplest, but leaves nonce blocking unaddressed. Users still hit stuck-tx problems every day.

### Why not E

- Highest timeline risk. Core-dev feedback explicitly against bundling permissions.
- SENDER-frame `msg.sender` rule change is a core invariant — every client re-audits, every tool re-tests.
- The incremental UX delta over D is narrow because ~85 % of the permissions story is deliverable via contract-layer work on top of D.
- The ratio of review burden to incremental user-visible win is worst in E.

### Why D wins

1. **Core-dev-acceptable.** Every change has independent precedent. No consensus paradigm shift. Cross-client test surface is real but bounded.
2. **Resilient.** Any one piece can be deferred without invalidating the others.
3. **Wallet-impactful.** Solves nonce blocking and stale signatures — the two most user-visible EOA gaps.
4. **Application-extensible.** Contract layer + wallet code can deliver ~85 % of the permissions UX without further consensus work. Session keys ship this year in software, not next year in a fork.
5. **Execution-authority pathway.** The narrow `msg.sender = delegator` gap remains a legitimate later-fork target. Once D ships and 7710-on-EOA-via-default-code gets real usage, the requirements for the follow-on permissions fork sharpen.

### Bottom line

**Ship D in the AA fork. Ship permissions v2 as a follow-on fork once `execution_authority` is settled.**

The meta-pattern: every feature that can land in contracts + wallet code instead of consensus should. D is the minimum protocol surface that lets this pattern actually play out for permissions — because without 2D nonces (lane isolation), validity windows (temporal bounds), and guarantors (mempool admission for shared-state caveats), contract-layer session keys don't work well enough to defer the protocol-layer version. D is the fork that lets permissions wait without hurting users.

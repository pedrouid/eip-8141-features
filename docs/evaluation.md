# Evaluation — Fork Scope Scenarios for EIP-8141

_Author: Claude. Scratch doc, not indexed on the site. Evaluates five candidate fork-scope combinations and recommends the best compromise._

Scenarios:

- **A**: guarantor only
- **B**: guarantor + 2D nonces
- **C**: guarantor + validity windows
- **D**: guarantor + 2D nonces + validity windows
- **E**: guarantor + 2D nonces + validity windows + permissions

Each assumes base EIP-8141 ships in the same fork.

**Weighting.** Core-dev feedback weighted higher than wallet-dev because core devs implement and carry consensus risk. Every scenario also considers:

- **Today's wallet stack** — what wallet devs already build against (ERC-4337, ERC-7710, bundlers, paymasters).
- **Layering without waiting for the next fork** — what the wallet + contract layer can deliver on top.

The biggest compromise lever: every feature movable to contracts or wallet code shrinks the fork. Many features thought to need protocol changes are achievable via the existing ERC-4337 / 7710 ecosystem with modest adaptation.

## Scenario A — Guarantor only

**Changes**: 0 envelope fields, 0 canonical contracts, 1 APPROVE scope (`guarantee`), 1 tx-scoped field, mempool relaxation for shared-state reads with guarantor backing.

**Core-dev**: smallest possible addition. Main review surface is the mempool relaxation — guarantors route shared-state-read risk from policy violation into economic risk. VOPS invariant preserved. PR #11555 still iterating. **Low risk.**

**Wallet-dev**: infrastructure-layer win (ERC-20 paymasters on public mempool; privacy flows). Doesn't solve nonce blocking, stale sigs, session keys.

**Today's stack**: ERC-4337 + EntryPoint + bundlers; offchain paymasters; ERC-7710 for smart-account wallets.

**Layering**: paymasters propagate publicly without bundlers. Everything else stays on ERC-4337. Nonce blocking and stale signatures persist.

**Verdict**: ships easily, user delta minimal.

## Scenario B — Guarantor + 2D Nonces

**Changes**: 1 envelope field (`nonce_key: uint256`), 1 system contract (`NonceLaneRegistry`, EIP-4788 pattern), pre-tx system-call, per-lane mempool rules, `eth_getTransactionCountByKey` RPC.

**Core-dev**: two independent changes with clear precedent. Registry follows EIP-4788 / EIP-2935. State-growth bounded by SSTORE cost + mempool caps. FOCIL needs cross-client tests on per-lane RBF. **Moderate risk.** Registry pivot eliminates the account-encoding objection.

**Wallet-dev**: wallet UX breakthrough for stuck-tx problem. Missing: stale-sig protection, session keys.

**Today's stack**: ERC-4337 2D nonces (smart accounts only); EOAs juggle multiple addresses.

**Layering**: native 2D nonces universally. Validity windows still work via VERIFY-frame `block.timestamp` workaround but drop to expansive/private tiers. Session keys via 2D-nonce lanes become viable (scoped signers on user's own account, isolated per-lane). ERC-4337 + 7710 continues for delegated execution where `msg.sender` must differ.

**Verdict**: biggest single UX win but omits cheap-to-add validity windows.

## Scenario C — Guarantor + Validity Windows

**Changes**: 2 envelope fields (`valid_after`, `valid_before`), 0 canonical contracts, pre-tx time check. No state, no contracts.

**Core-dev**: cleanest addition. Envelope-only, deterministic, FOCIL-friendly, zero VOPS impact. Core-dev feedback: "easiest to standardize." **Very low risk.**

**Wallet-dev**: most user-safety-positive. Swaps expire, limit orders die at deadline, scheduled payments activate. Easy to display; hardware-wallet-friendly. Missing: nonce blocking.

**Today's stack**: ERC-4337 `validUntil`/`validAfter` in UserOperation; EOAs use dapp-side calldata tricks.

**Layering**: universal native expiry day one. Short-lived delegations become safer (defense in depth for PQ). Nonce blocking persists.

**Verdict**: good safety floor, less UX ceiling than B.

## Scenario D — Guarantor + 2D Nonces + Validity Windows

**Changes**: 3 envelope fields, 1 canonical contract, pre-tx checks for time-window and nonce-lane, combined mempool rules.

**Core-dev**: three independent features on their own merits. Validity windows minimal; 2D nonces bounded via registry; guarantors small surface. Three largely orthogonal. Cross-proposal interactions (future-valid tx reserving its lane, RBF across `(sender, nonce_key, tx.nonce)`, stream-advance under guarantor-paid failure) need cross-client tests. All implementable. **Moderate risk.** **Resilience**: any one can be pulled without invalidating the others.

**Wallet-dev**: complete UX package for EOAs without delegated permissions — no stuck txs, no stale sigs, paymaster coverage, scheduled txs on their own lanes.

**Today's stack**: full ERC-4337 / ERC-7710 + smart-account 2D nonces + offchain session keys.

**Layering — the killer insight**: with all three primitives, ~85 % of the permissions UX is achievable in contracts + wallet code:

1. **Session keys via 2D-nonce lanes + validity-window expiry.** Wallet dedicates a lane per dapp. Session key is a scoped signer on user's account, allowed by custom default-code only for that dapp's lane, within a validity window. `tx.sender` stays the user.
2. **Short-term delegations** — delegator pre-signs a tx with tight validity window; delegate submits.
3. **Recovery / admin** on reserved lanes with guardian signatures.
4. **Scheduled transactions** via `valid_after` as a native primitive.
5. **Stateless ERC-7710 on EOA default-code.** Delegate submits; DelegationManager verifies offchain delegation signature, runs caveats, CALLs targets with `msg.sender = manager`. Works because pre-approval configuration suffices for ERC-20 and allowlisted flows.
6. **Guarantor-backed shared-state caveats** propagate publicly via PR #11555.

What still requires `execution_authority` (later fork): delegated flows where `msg.sender` must literally be the delegator — the narrow case ERC-4337 / 7710 already handle via smart accounts.

**Pivotal argument**: D enables ~85 % of delegated-permissions UX via contract-layer work, deferring only the narrow `msg.sender = delegator` case. Wallets ship session keys in software, not in a year-out fork.

## Scenario E — D + Permissions

**Changes**: D's changes + `DelegationManager` system contract, `execution_authority` tx-scoped state, generalized `APPROVE(execution)`, SENDER-frame `msg.sender` rule change, default-code surface expansions (`validateAuth`, delegation branch, `consumeAndFinalize` post-op, `sender_frames`), canonical caveat vocabulary, mempool permissions profile, ERC-7715.

**Core-dev**: large scope. Two system contracts; two tx-scoped state variables; a core-invariant change (SENDER `msg.sender` rule) every client must implement carefully; manager VOPS profile; multiple default-code surface additions; PQ migration complexity. Core-dev feedback was explicit: do not bundle permissions with base 8141 unless the full 8-item fork-scope inclusion list is settled. **High risk.**

**Wallet-dev**: everything users hoped smart wallets would deliver, on EOAs. Wallet work large: role-separated prompts, revocation UI, canonical caveat rendering, PQ migration workflow, SDK schemas. Wallet-dev wary: user safety depends on strong display + revocation and a narrow v1.

**Today's stack**: D + production ERC-7710/7715 via MetaMask.

**Layering**: E closes the `msg.sender = delegator` gap D cannot cover. But contracts + wallet code already deliver ~85 % on D. Incremental delta is narrow; ratio of review burden to incremental user win is worst in E.

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
| Permissions UX via contract-layer on top | ~30 % | ~50 % | ~40 % | **~85 %** | 100 % |
| Timeline risk | low | moderate | very low | moderate | high |

## Conclusion — best compromise

**Scenario D is the best compromise.**

Core-dev feedback weighted highest: D is the largest fork where every reviewed item has a clear path. Validity windows ship cleanly; 2D nonces post registry-pivot avoid account-encoding changes and reuse EIP-4788 / EIP-2935 precedent; guarantors are a bounded mempool-admission rule. None introduce a core-invariant change. Each can be pulled independently.

Wallet-dev feedback confirms: D delivers the concrete UX wins users complain about most. The gap D leaves (full delegated execution) is narrow enough that contracts + wallet code cover ~85 %.

### Permissions deferral (the core lever)

D lets permissions ship as software:

- Session keys as scoped signers on user's account, isolated on 2D-nonce lanes, bounded by validity windows.
- Dapp allowances via ERC-7710-style DelegationManager contracts; `msg.sender = manager` for ERC-20 and allowlisted flows.
- Scheduled payments native via `valid_after`.
- Recovery / admin on reserved lanes + guardian signatures in custom default-code.
- Guarantor-backed shared-state caveats via PR #11555.

Ecosystem does not need a hard fork this year for session-key UX.

### Why not A, B, C, or E

- **A**: ships easily, leaves users with essentially today's UX.
- **B**: biggest single UX win but omits cheap validity windows.
- **C**: safest and simplest but leaves stuck-tx problems unaddressed.
- **E**: highest timeline risk. Core-dev feedback against bundling. SENDER-`msg.sender` rule change is a core invariant every client re-audits. Incremental UX delta over D is narrow because ~85 % of permissions is deliverable via contract-layer work on D.

### Why D wins

1. Core-dev-acceptable. Every change has independent precedent. No consensus paradigm shift.
2. Resilient. Any piece pull-able without invalidating others.
3. Wallet-impactful. Solves the two most user-visible EOA gaps.
4. Application-extensible. Contracts + wallet code deliver ~85 % of permissions UX.
5. Execution-authority pathway. Narrow `msg.sender = delegator` gap is a legitimate later-fork target.

### Bottom line

**Ship D. Ship permissions v2 as a follow-on fork once `execution_authority` is settled.**

Meta-pattern: every feature landable in contracts + wallet code instead of consensus should. D is the minimum protocol surface that lets this play out for permissions — without 2D nonces (lane isolation), validity windows (temporal bounds), and guarantors (mempool admission for shared-state caveats), contract-layer session keys don't work well enough to defer the protocol version. D is the fork that lets permissions wait without hurting users.

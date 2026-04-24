# EIP-8141 Primitive: Guarantors

*Author: Claude. Scratch doc, not indexed on the site. Assumes PR #11555 (derekchiang, Apr 22) lands in roughly its proposed shape; the design is still iterating and the exact flags/scopes may change.*

## What guarantors are

PR #11555 introduces a **guarantor payer**: a party that commits to paying gas *even if sender validation fails*. When a transaction carries a guarantor, mempool nodes may skip sender-VERIFY simulation entirely and propagate on the strength of the guarantor's signature alone. If on-chain execution reveals that sender VERIFY would have failed, the guarantor absorbs the gas.

Two mechanical effects for the proposals already written:

1. **A new payer role and almost-certainly a new APPROVE scope** (or equivalent flag) for guarantee.
2. **A two-branch gas-payment model**: sender pays if their VERIFY succeeds, guarantor pays otherwise.

Everything else — VOPS compatibility, the validation-tier split, nonce consumption semantics — follows from those two.

Key property the feedback review cares about: **guarantors route shared-state reads from a mempool-policy problem into an economic-risk problem**. A caveat that reads an ERC-20 balance is now mempool-admissible if a guarantor is backing the tx. This substantially expands what the permissions proposal's caveats can do.

## Protocol surface added

Even though the PR is still iterating, the shape is predictable:

- **New APPROVE scope (or equivalent flag).** Likely `APPROVE(guarantee)` — a scope a VERIFY frame targeting the guarantor can call to declare the guarantor's commitment. The current scopes `payment`, `execution`, and their combination expand by one.
- **New tx-scoped state** `guarantor: Optional[address]` set on `APPROVE(guarantee)`. Distinct from `payer_approved`.
- **Gas-payment resolution rule** at inclusion time:
  - sender VERIFY succeeded → payer (normal rules) pays.
  - sender VERIFY failed → guarantor pays.
- **Mempool validation relaxation** conditional on a valid guarantor commitment: sender-VERIFY simulation is skippable. The guarantor's own VERIFY still must fit the restrictive tier (no shared-state reads there).

## Nonce consumption

Confirmed by the reviewer's concern set and the feedback doc:

- **Nonce is consumed on inclusion, regardless of whether sender VERIFY succeeded.** The tx is in the block; replay protection depends on the stream advancing.
- **Sender's stream moves forward even on VERIFY failure.** The sender simply retries on the next sequence.
- **Guarantor griefing is economically bounded.** A guarantor who backs a tx whose VERIFY will fail burns their own gas. Market forces, not protocol rules, shape this.

This is the right semantic for 2D nonces: always-advance on inclusion keeps the stream model clean and monotone.

---

## Impact on the 2D-nonces proposal

**Small, mostly confirming.**

- The "nonce advances on inclusion, VERIFY outcome is separate" rule pairs naturally with 2D nonces: per-stream sequence is monotone on inclusion, independent of VERIFY success.
- Mempool readiness per `(sender, nonce_key, tx.nonce)` is unaffected — the guarantor commitment is an additional validation piece, not a substitute for the nonce check.
- No changes to the spec delta for 2D nonces.
- One clarification worth adding to the 2D-nonces proposal: "inclusion advances the stream; VERIFY failure does not roll back the stream counter." This is the correct semantic and is reinforced, not complicated, by guarantors.

**Net**: guarantors don't require 2D-nonces redesign. They just pin a semantic choice that was implicit.

---

## Impact on the permissions proposal

**Substantial. This is where guarantors matter.**

### 1. Caveats can now read shared state

The current permissions proposal restricts caveats to what the restrictive tier allows. That forbids reading ERC-20 balances, allowlist contracts, environmental opcodes, or anything outside `tx.sender`'s storage. Many useful caveats (spend-limit based on current balance, target-contract allowlist, oracle-bounded permissions) violate this.

With a guarantor backing the tx, the delegator's VERIFY (where caveats run) can read shared state and still propagate through public mempool. **The caveat design space roughly doubles.**

Concrete caveats unlocked:

- "Transfer only if recipient is in allowlist contract X" (reads X's storage).
- "Spend up to 10% of current ERC-20 balance" (reads the ERC-20).
- "Allow trade only if oracle price < Y" (reads oracle contract).
- "Revoke after N on-chain events" (reads event-tracking contract).

Without guarantors, these caveats force delegation flows into the expansive/private mempool. With guarantors, they propagate publicly.

### 2. Three-role gas model, potentially four

A fully delegated tx can now have:

- `tx.sender` = delegate (signs, consumes tx-level nonce).
- `execution_authority` = delegator (SENDER frames run as them — see `execution-authority.md`).
- payer = sponsor (paid via `APPROVE(payment)`).
- guarantor = whoever underwrites sender-VERIFY risk (paid via `APPROVE(guarantee)` if sender VERIFY fails).

Payer and guarantor are distinct. The sponsor pays on success, the guarantor pays on failure. In many cases the same party plays both roles, but they are specified independently.

### 3. Who is the guarantor in a delegation flow?

Four plausible candidates, each with different trust/economic properties:

- **Delegate (self-guarantee).** Delegate wants the redemption to work; backing their own tx costs them only the downside gas.
- **Delegator.** Delegator trusts their own manager's judgment and absorbs the cost of caveat failures.
- **Manager contract.** A canonical or specialized manager could hold a staked bond and guarantee redemptions it validates.
- **Third-party paymaster.** AMM-backed or commercial guarantor services, similar to today's 4337 paymasters but with a different risk profile.

The permissions proposal should enumerate these and pick a default. My current take: **manager-as-guarantor** is the cleanest fit — the manager is already the trust anchor for caveat evaluation; having it stake gas for the redemptions it approves aligns incentives. But the choice is a design question, not a forced conclusion.

### 4. New APPROVE scope affects the frame count

Current permissions examples have 2-4 frames. With guarantors, add one more VERIFY frame for the guarantor's approval. A typical redemption becomes:

| Frame | Mode | Target | Role |
|---|---|---|---|
| 0 | VERIFY | guarantor | `APPROVE(guarantee)`; mempool-skippable for sender VERIFY |
| 1 | VERIFY | delegator | Delegation bundle → manager.isAuthorized → `APPROVE(execution)` |
| 2 | VERIFY | sponsor (optional) | `APPROVE(payment)` |
| 3 | SENDER | target | Delegated action |

The permissions proposal's current spec delta needs an item: "an optional guarantor VERIFY frame can precede the delegator VERIFY frame and unlock shared-state reads in caveats."

### 5. Manager may issue the guarantee itself

If manager-as-guarantor becomes the default, the manager contract's interface grows:

```solidity
function guaranteeAndAuthorize(
    Delegation bundle,
    Frame[] pendingFrames
) external returns (bool authorized, uint256 maxGasGuaranteed);
```

This single call both evaluates the delegation (including shared-state-reading caveats) and commits manager funds to cover gas if something goes wrong. The manager now holds a gas pool — a real operational concern, but one the manager contract is well-placed to manage.

---

## Interaction with the other primitives

- **Sighash binding**: unaffected. Guarantor commitment is a fresh tx-scoped state set by an APPROVE variant; no change to what's in or out of sighash.
- **Execution authority**: orthogonal. A tx can have execution authority delegated (delegator) and a guarantor (manager). Both set via different `APPROVE` scopes in different VERIFY frames.
- **2D nonces**: clarified rather than changed. Stream advances on inclusion regardless of sender VERIFY outcome.

---

## Spec delta (as far as we can predict it)

1. Add `APPROVE(guarantee)` scope (or equivalent flag).
2. Add tx-scoped state `guarantor: Optional[address]`, set by a VERIFY frame targeting the guarantor that calls `APPROVE(guarantee)`.
3. Gas-payment rule: sender VERIFY success → payer pays; sender VERIFY failure → guarantor pays.
4. Mempool rule: if a valid guarantor commitment is present and guarantor VERIFY fits restrictive tier, sender VERIFY simulation may be skipped. Shared-state reads in sender VERIFY become mempool-admissible.
5. Nonce semantics explicit: stream advances on inclusion regardless of sender VERIFY outcome.

---

## Summary

Guarantors are small in protocol surface (one new APPROVE scope, one new tx-scoped field, one mempool relaxation) but substantial in downstream effect. They unlock shared-state-reading caveats for any future delegated-permissions layer, enable public-mempool ERC-20 paymasters, and confirm the 2D-nonces semantic that streams advance on inclusion regardless of VERIFY outcome.

## Position across the scenario set

Per `evaluation.md` and `plan.md`, guarantors are included in **every scenario** (A through E) as the smallest valuable addition beyond base EIP-8141. The generic guarantor primitive lands in the base AA fork alongside 2D nonces and validity windows.

**Manager-as-guarantor is explicitly deferred to permissions v2** (per Q10 in `research.md`). The generic primitive ships in the base fork; the specific use inside a canonical DelegationManager contract (with its associated gas-pool economics, staking/slashing rules, and revocation interactions) ships with the permissions EIP in a later fork. This keeps the generic primitive's timeline decoupled from manager-contract iteration.

Until permissions ships, guarantors enable:

- ERC-20 paymasters with trustless onchain verification on the public mempool.
- Privacy flows with nullifier reads.
- Complex AA validation where a third party underwrites the shared-state-read risk.

What they do **not** yet enable (pending permissions v2):

- Manager-as-guarantor for DelegationManager flows.
- Restrictive-tier shared-state caveats in delegated permissions.

If PR #11555 does not land in the base AA fork, the permissions v2 design has to re-litigate the guarantor interface in its own fork scope, which is material additional review burden. The generic guarantor primitive is therefore worth landing in the base fork independent of whether permissions are in scope for that fork.

# EIP-8141 Primitive: Guarantors

_Author: Claude. Scratch doc, not indexed on the site. Assumes PR #11555 (derekchiang, Apr 22) lands in roughly its proposed shape; the design is still iterating and the exact flags/scopes may change._

## What guarantors are

PR #11555 introduces a **guarantor payer**: a party that commits to paying gas even if sender validation fails. When a tx carries a guarantor, mempool nodes may skip sender-VERIFY simulation entirely and propagate on the strength of the guarantor's signature alone. If on-chain execution reveals that sender VERIFY would have failed, the guarantor absorbs the gas.

Two mechanical effects:

1. A new payer role and an APPROVE scope for guarantee.
2. A two-branch gas-payment model: sender pays on VERIFY success, guarantor pays otherwise.

Key property: guarantors route shared-state reads from a mempool-policy problem into an economic-risk problem. A caveat reading an ERC-20 balance becomes mempool-admissible when a guarantor backs the tx.

## Protocol surface added

- **`APPROVE(guarantee)`** scope, called by a VERIFY frame targeting the guarantor.
- **`guarantor: Optional[address]`** tx-scoped state, set on `APPROVE(guarantee)`. Distinct from `payer_approved`.
- **Gas-payment resolution** at inclusion time: sender VERIFY success → payer pays; sender VERIFY failure → guarantor pays.
- **Mempool relaxation** conditional on a valid guarantor commitment: sender-VERIFY simulation skippable. The guarantor's own VERIFY still fits restrictive tier.

## Nonce consumption

- Nonce consumed on inclusion regardless of sender VERIFY outcome.
- Sender's stream advances even on VERIFY failure; sender retries next sequence.
- Guarantor griefing is economically bounded: a guarantor backing a failing tx burns their own gas.

This confirms the 2D-nonces "always-advance on inclusion" invariant.

## Impact on 2D nonces

Small, confirming. Per-stream sequence is monotone on inclusion independent of VERIFY success. Mempool readiness unaffected — the guarantor commitment is additional validation, not a substitute for the nonce check. No spec changes to 2D nonces; the stream-advance rule is now a pinned normative invariant there.

## Impact on permissions

Substantial. Without guarantors, caveats can't read shared state and stay restrictive-tier. With guarantors:

- **Caveat design space doubles.** Unlocks "transfer only if recipient in allowlist X," "spend up to 10 % of current ERC-20 balance," "allow trade only if oracle price < Y," "revoke after N on-chain events."
- **Three- or four-role gas model.** `tx.sender` = delegate; `execution_authority` = delegator; payer = sponsor (on success); guarantor = underwriter (on failure). Payer and guarantor distinct.
- **Typical redemption grows to 3–4 frames**: guarantor VERIFY → delegator VERIFY → (optional sponsor VERIFY) → SENDER.

## Position across the scenario set

Per `evaluation.md` and `plan.md`, guarantors are in every scenario (A–E) as the smallest valuable addition beyond base EIP-8141. The generic primitive ships in the base AA fork.

**Manager-as-guarantor is deferred to permissions v2** (Q10 in `research.md`). Generic primitive lands now; the specific use inside a canonical DelegationManager — with gas-pool economics, staking/slashing rules, revocation interactions — ships with permissions later. Decouples timelines.

Until permissions ships, guarantors enable:

- ERC-20 paymasters with trustless onchain verification on the public mempool.
- Privacy flows with nullifier reads.
- Complex AA validation where a third party underwrites shared-state-read risk.

Not yet enabled (permissions v2): manager-as-guarantor; restrictive-tier shared-state caveats in delegated permissions.

## Interaction with other primitives

- **Sighash binding**: unaffected.
- **Execution authority**: orthogonal. A tx can have both `execution_authority = delegator` and `guarantor = third-party` via different APPROVE scopes in different VERIFY frames.
- **2D nonces**: confirms the stream-advance invariant.

## Spec delta

1. Add `APPROVE(guarantee)` scope.
2. Add tx-scoped state `guarantor: Optional[address]`.
3. Gas-payment rule: sender VERIFY success → payer pays; failure → guarantor pays.
4. Mempool rule: if a valid guarantor commitment is present and guarantor VERIFY fits restrictive tier, sender-VERIFY simulation skippable; shared-state reads in sender VERIFY become mempool-admissible.
5. Nonce semantics: stream advances on inclusion regardless of sender VERIFY outcome.

## Summary

Small surface (one APPROVE scope, one tx-scoped field, one mempool relaxation); substantial downstream effect. Unlocks shared-state caveats for any future delegated-permissions layer, enables public-mempool ERC-20 paymasters, confirms the stream-advance invariant.

If PR #11555 doesn't land in the base fork, permissions v2 re-litigates the guarantor interface in its own fork — material extra review burden. The generic primitive is worth landing independently of whether permissions are in scope.

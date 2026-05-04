# EIP-8141 Primitive: Guarantors

```
Canonical for:  APPROVE(guarantee), tx-scoped guarantor field, mempool relaxation
Referenced by:  every alternative
```

_Assumes PR #11555 (derekchiang, Apr 22) lands in roughly its proposed shape; the design is still iterating and the exact flags/scopes may change. Bundled with every alternative; the proposals all ship "EIP-8141 + guarantors + the proposal's features."_

## What guarantors are

PR #11555 introduces a **guarantor payer**: a party that commits to paying gas even if sender validation fails. When a tx carries a guarantor, mempool nodes may skip sender-VERIFY simulation entirely and propagate on the strength of the guarantor's signature alone. If on-chain execution reveals that sender VERIFY would have failed, the guarantor absorbs the gas.

Two mechanical effects:

1. A new payer role and an APPROVE scope for guarantee.
2. A two-branch gas-payment model: sender pays on VERIFY success, guarantor pays otherwise.

Key property: guarantors route shared-state reads from a mempool-policy problem into an economic-risk problem. A VERIFY frame reading an ERC-20 balance becomes mempool-admissible when a guarantor backs the tx.

## Protocol surface added

- **`APPROVE(guarantee)`** scope, called by a VERIFY frame targeting the guarantor.
- **`guarantor: Optional[address]`** tx-scoped state, set on `APPROVE(guarantee)`. Distinct from `payer_approved`.
- **Gas-payment resolution** at inclusion time: sender VERIFY success → payer pays; sender VERIFY failure → guarantor pays.
- **Mempool relaxation** conditional on a valid guarantor commitment: sender-VERIFY simulation skippable. The guarantor's own VERIFY still fits restrictive tier.

## Nonce consumption

- Nonce consumed on inclusion regardless of sender VERIFY outcome.
- Sender's stream advances even on VERIFY failure; sender retries next sequence.
- Guarantor griefing is economically bounded: a guarantor backing a failing tx burns their own gas.

This pins the flexible-nonces "always-advance on inclusion" invariant.

## Position across the alternatives

Guarantors ship in every alternative: each proposal assumes "EIP-8141 + guarantors + the proposal's added features." The primitive is small, independently valuable, and confirms invariants the other features rely on.

Independently of any other feature, guarantors enable:

- ERC-20 paymasters with trustless onchain verification on the public mempool.
- Privacy flows with nullifier reads.
- Complex AA validation where a third party underwrites shared-state-read risk.

## Impact on flexible nonces

Small, confirming. Per-stream sequence is monotone on inclusion independent of VERIFY success. Mempool readiness unaffected; the guarantor commitment is additional validation, not a substitute for the nonce check. No spec changes to flexible nonces; the stream-advance rule is now a pinned normative invariant in any alternative that includes flexible nonces (`flexible-nonces.md`, `key-lanes.md`, `authorization-scopes.md`).

The dependence runs both ways. A guarantor sponsoring many txs in parallel must advance a nonce per sponsorship for replay protection but cannot serialise every sponsorship through a single guarantor nonce without bottlenecking throughput. Flexible nonces give each sponsorship its own stream, which is why broad guarantor adoption is more tractable when flexible nonces are also in scope. The combination is still being scoped; whether the two features ship in the same upgrade or flexible nonces precede via a separate EIP is an open coordination question.

## Interactions with other primitives

- **flexible nonces**: confirms stream-advance invariant.
- **Validity windows**: orthogonal. If a tx expires between admission and inclusion, mempool drops it; guarantor doesn't pay for non-includable txs.
- **Signer binding**: orthogonal. A guarantor-backed tx may include binding PQ VERIFY frames; the guarantor's commitment is independent.
- **Sighash binding**: unaffected.

## Spec delta

1. Add `APPROVE(guarantee)` scope.
2. Add tx-scoped state `guarantor: Optional[address]`.
3. Gas-payment rule: sender VERIFY success → payer pays; failure → guarantor pays.
4. Mempool rule: if a valid guarantor commitment is present and guarantor VERIFY fits restrictive tier, sender-VERIFY simulation skippable; shared-state reads in sender VERIFY become mempool-admissible.
5. Nonce semantics: stream advances on inclusion regardless of sender VERIFY outcome.

## Summary

Small surface (one APPROVE scope, one tx-scoped field, one mempool relaxation); substantial downstream effect. Enables public-mempool ERC-20 paymasters and confirms the stream-advance invariant relied on by flexible nonces. Bundled into every alternative; independently valuable even if every other feature is dropped.

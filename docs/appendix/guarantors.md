# EIP-8141 Primitive: Guarantors

```
Canonical for:  guarantor payer semantics, draft PR #11555, mempool relaxation
Referenced by:  every alternative
```

_Origin: [PR #11555](https://github.com/ethereum/EIPs/pull/11555) (derekchiang, Apr 22). The consolidated [`/eip-8141.md`](../../EIPS/eip-8141.md) folds guarantors directly into the EIP; the standalone proposals in this repo all ship "EIP-8141 + guarantors + the proposal's features." Encoding choices below match the consolidated draft._

## What guarantors are

A **guarantor payer** is a party that commits to paying gas even if sender validation fails. When a tx carries a guarantor commitment, mempool nodes may skip sender-VERIFY simulation entirely and propagate on the strength of the guarantor's signature alone. If on-chain execution reveals that sender VERIFY would have failed, the guarantor absorbs the gas.

Two mechanical effects:

1. A new payer role, surfaced via the `APPROVE_GUARANTEE = 0x4` scope value on the existing `APPROVE` opcode.
2. A two-branch gas-payment model: payer pays on `payer_approved`, guarantor pays otherwise.

Key property: guarantors route shared-state reads from a mempool-policy problem into an economic-risk problem. A VERIFY frame reading an ERC-20 balance becomes mempool-admissible when a guarantor backs the tx.

## Protocol surface added

- **`APPROVE_GUARANTEE` scope** (`0x4`): a third bit in the APPROVE scope mask, used by a VERIFY frame whose target commits to underwriting the tx.
- **`guarantor_approved: bool`** and **`guarantor: Optional[address]`** tx-scoped state, set by `APPROVE(APPROVE_GUARANTEE)`. Distinct from `payer_approved`.
- **Gas-payment resolution** at inclusion time: if `payer_approved == true`, payer pays; otherwise if `guarantor_approved == true`, guarantor pays; otherwise tx is invalid.
- **Validity exception** for the covered sender VERIFY frame: a sender VERIFY that exits without calling APPROVE is allowed (recorded as `frame.status = 0`) when `guarantor_approved == true` and the frame is at `guarantor_index + 1`. Subsequent SENDER frames are skipped while `sender_approved == false`.
- **Per-frame signature hash** at `TXPARAM(0x0B)` (= `compute_frame_sig_hash(tx, currently_executing_frame_index)`): elides only the current frame's data, preserves every other VERIFY frame's data. Lets a guarantor sign a digest that binds the sender VERIFY data it is underwriting without self-referencing its own signature bytes.
- **Mempool relaxation** conditional on a valid guarantor commitment: sender-VERIFY simulation skippable. The guarantor's own VERIFY still fits restrictive tier.

## Nonce consumption

- Nonce consumed on inclusion regardless of sender VERIFY outcome.
- Sender's stream advances even on VERIFY failure; sender retries next sequence.
- Guarantor griefing is economically bounded: a guarantor backing a failing tx burns their own gas.

This pins the Flexible-nonces "always-advance on inclusion" invariant.

## Position across the alternatives

Guarantors ship in every alternative: each proposal assumes "EIP-8141 + guarantors + the proposal's added features." The primitive is small, independently valuable, and confirms invariants the other features rely on.

Independently of any other feature, guarantors enable:

- ERC-20 paymasters with trustless onchain verification on the public mempool.
- Privacy flows with nullifier reads.
- Complex AA validation where a third party underwrites shared-state-read risk.

## Impact on Flexible nonces

Small, confirming. Per-stream sequence is monotone on inclusion independent of VERIFY success. Mempool readiness unaffected; the guarantor commitment is additional validation, not a substitute for the nonce check. No spec changes to Flexible nonces; the stream-advance rule is now a pinned normative invariant in any alternative that includes Flexible nonces (`flexible-nonces.md`, `key-streams.md`, `auth-scopes.md`).

The dependence runs both ways. A guarantor sponsoring many txs in parallel must advance a nonce per sponsorship for replay protection but cannot serialise every sponsorship through a single guarantor nonce without bottlenecking throughput. Flexible nonces give each sponsorship its own stream, which is why broad guarantor adoption is more tractable when Flexible nonces are also in scope. The combination is still being scoped; whether the two features ship in the same upgrade or Flexible nonces precede via a separate EIP is an open coordination question.

## Interactions with other primitives

- **Flexible nonces**: confirms stream-advance invariant.
- **Upstream expiry verifier frame** (and the historical Envelope-expiry / Validity-windows alternatives): orthogonal. If a tx expires between admission and inclusion, mempool drops it; guarantor doesn't pay for non-includable txs.
- **Signer binding**: orthogonal. A guarantor-backed tx may include binding PQ VERIFY frames; the guarantor's commitment is independent.
- **Sighash binding**: unaffected.

## Spec delta

1. Add a guarantor commitment path.
2. Add tx-scoped state `guarantor: Optional[address]`.
3. Gas-payment rule: sender VERIFY success → payer pays; failure → guarantor pays.
4. Mempool rule: if a valid guarantor commitment is present and guarantor VERIFY fits restrictive tier, sender-VERIFY simulation skippable; shared-state reads in sender VERIFY become mempool-admissible.
5. Nonce semantics: stream advances on inclusion regardless of sender VERIFY outcome.

## Summary

Small surface (one commitment path, one tx-scoped field, one mempool relaxation); substantial downstream effect. Enables public-mempool ERC-20 paymasters and confirms the stream-advance invariant relied on by Flexible nonces. Bundled into every alternative; independently valuable even if every other feature is dropped.

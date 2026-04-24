# EIP-8141 Primitive: Sighash Binding for Protocol-Visible Frame Data

*Author: Claude. Scratch doc, not indexed on the site. Prerequisite for the 2D-nonces and permissions proposals.*

## Problem

EIP-8141's `compute_sig_hash` elides VERIFY frame data. This is load-bearing: the signature itself lives in VERIFY calldata for default-code transactions, so it cannot be part of its own hash.

Both the 2D-nonces and permissions proposals placed protocol-visible data inside VERIFY calldata:

- **2D nonces**: a 40-byte `(nonce_key, nonce_seq)` prefix.
- **Permissions**: a `DELEGATION_MARKER` + delegation bundle.

The elision means none of it is bound by the transaction signature. Any party with access to the signed bytes can rewrite the prefix or the bundle and still produce a valid `tx.signature`. This is a correctness bug, not a style concern.

This document resolves the binding for each proposal without inventing a new envelope field per feature.

---

## Two classes of protocol-visible data

The two proposals need different binding strategies, and conflating them was the source of my earlier mistake.

### Class A: data whose validity depends only on the transaction

Stream key and sequence for 2D nonces belong here. There is no account-side signature that covers them; the consensus check happens before any account code runs. If the tx signature doesn't cover the key, nothing does.

**Class A data must be bound by the tx sighash.**

### Class B: data whose validity depends on an independent account-side signature

The delegation bundle belongs here. The delegator signs a canonical digest offchain (never in the tx), and the manager verifies that signature via `validateAuth`. The delegation bundle in VERIFY calldata is only a carrier for data the delegator has already signed elsewhere.

**Class B data does not require tx-sighash coverage.** Its integrity comes from the delegator's independent signature over a self-contained digest.

Confusing these classes is what led me to put everything in VERIFY calldata and claim sighash changes weren't needed.

---

## Binding for Class A (2D nonces)

Two viable designs. The reviewer recommended the second; I agree.

### Design A1 — Structured VERIFY layout, sighash covers the non-signature prefix

Change the VERIFY calldata convention to:

```
VERIFY.data = [protocol_prefix][sig_type][sig_payload]
```

Change `compute_sig_hash` to elide only `[sig_type][sig_payload]` rather than all of VERIFY data. `[protocol_prefix]` (which could carry nonce_key, nonce_seq, delegation markers, future protocol fields) is covered.

- Pro: one-time rule change, extensible for any future protocol-visible VERIFY data.
- Con: every default-code implementation must be updated to skip the prefix before parsing its signature; existing signature-type encoding (first byte of `frame.data` is `signature_type` today) breaks unless the default-code signature layout is also changed.
- Con: "sighash changes" is a larger consensus surface than a single envelope field.

### Design A2 — Envelope field for `nonce_key`, `tx.nonce` stays as the sequence

Add **one** envelope field `nonce_key: uint256`. Keep the existing envelope `nonce: uint64` as the sequence. Consensus check becomes:

```
require tx.nonce == state[tx.sender].nonces[tx.nonce_key]
```

- Pro: existing envelope `nonce` field retains a precise meaning (it's the sequence).
- Pro: clients and tooling have a single new RLP field to handle, no structural changes to VERIFY calldata.
- Pro: the nonce key is covered by the existing sighash for free — no sighash rule changes.
- Pro: no conflict with the default-code signature-type byte at the start of `frame.data`.
- Con: violates my earlier "no envelope changes" stance.

### Recommendation for Class A: Design A2

The earlier "no envelope changes" stance was too strict. It was a design aesthetic, not a principled constraint. One envelope field is cheaper in consensus surface, client implementation cost, and client-side parsing ambiguity than a VERIFY-layout restructure plus a sighash rule change. It is also what Tempo does for the same reason.

**Implication for the 2D-nonces proposal:** revise to add `nonce_key: uint256` as an envelope field and let `tx.nonce` be the sequence. Remove the "first 40 bytes of APPROVE frame calldata" language entirely. The signed frame digest already covers the envelope.

---

## Binding for Class B (delegation bundle)

The bundle does not need to be in the tx sighash. The chain of binding is:

1. **Delegator authority** — delegator signs an offchain canonical delegation digest:

   ```
   delegationDigest = keccak256(
       chain_id,
       manager_addr,
       delegator,
       delegate,
       caveats_root,
       salt,
       expiry
   )
   ```

   This is self-contained and independent of any specific transaction.

2. **Authority proof** — manager calls `delegator.validateAuth(delegationDigest, proof)`. The account verifies the signature under whatever scheme it uses. No tx sighash involved.

3. **Action binding** — caveats inspect the transaction's SENDER frame content (targets, values, call data). Since SENDER frames are **not** elided from the tx sighash, the actions they describe are signed by the tx signer (the delegate). Caveats reading them are reading signed data.

4. **Replay protection** — `salt` + `expiry` in the delegation digest; plus delegation-redemption nonce tracked by the manager's state.

What binds a specific redemption to a specific tx: **the caveats evaluating signed SENDER frames.** If a spend-limit caveat reads that SENDER frame 1 calls `USDC.transfer(X, 10e6)`, the caveat is reading content covered by the tx sighash.

**Implication for the permissions proposal:** no sighash change is required, and no tx sighash binding of the bundle is needed. But the manager's `isAuthorized` must receive the SENDER frames (or their canonical hash) as an argument so caveats can evaluate signed action content. This is a protocol affordance on default code: it must be able to pass the signed portion of the tx to the manager.

---

## Protocol affordances required

For Class A (2D nonces), Design A2:

- One new envelope field `nonce_key: uint256`.
- Protocol nonce check updated.
- No sighash rule change.
- No VERIFY-layout change.

For Class B (permissions):

- Default code must have access to the list of SENDER frames (or a canonical hash / Merkle root) in tx-scoped context, sufficient to pass into `manager.isAuthorized`.
- That data is already covered by the tx sighash (SENDER frames are not elided).
- No sighash rule change. No envelope field.

---

## Summary

| Proposal | Class | Binding mechanism | Sighash change? | Envelope change? |
|---|---|---|---|---|
| 2D nonces | A | Envelope `nonce_key`, covered by existing sighash | No | **Yes, one field** |
| Permissions | B | Delegator signs independent digest; manager verifies via `validateAuth`; caveats inspect signed SENDER frames | No | No |

The earlier "no envelope changes anywhere" stance was wrong. 2D nonces warrant one envelope field because there is no account-side signature that can bind the stream key. Permissions does not warrant one because the delegation has its own independent signature chain.

# EIP-8141 Primitive: Sighash Binding for Protocol-Visible Frame Data

_Author: Claude. Scratch doc, not indexed on the site. Prerequisite for the 2D-nonces and permissions proposals._

## Problem

EIP-8141's `compute_sig_hash` elides VERIFY frame data. This is load-bearing: the default-code signature lives in VERIFY calldata, so it cannot be part of its own hash.

Both the 2D-nonces and permissions proposals once placed protocol-visible data inside VERIFY calldata (a 40-byte `(nonce_key, nonce_seq)` prefix; a `DELEGATION_MARKER` + bundle). The elision means none of it is bound by the transaction signature — an attacker with the signed bytes could rewrite the prefix or the bundle and still produce a valid `tx.signature`. Correctness bug, not a style concern.

This doc resolves the binding for each proposal.

## Two classes of protocol-visible data

### Class A: validity depends only on the transaction

Stream key and sequence for 2D nonces. No account-side signature covers them; the consensus check happens before any account code runs. If the tx signature doesn't cover the key, nothing does. **Class A must be bound by the tx sighash.**

### Class B: validity depends on an independent account-side signature

The delegation bundle. The delegator signs a canonical digest offchain (never in the tx); the manager verifies that signature via `validateAuth`. **Class B does not require tx-sighash coverage.** Integrity comes from the delegator's independent signature over a self-contained digest.

Conflating the classes is what led the earlier drafts to put everything in VERIFY calldata and claim no sighash changes were needed.

## Class A binding: 2D nonces

Two viable designs:

- **A1.** Structured VERIFY layout: `VERIFY.data = [protocol_prefix][sig_type][sig_payload]`. Change `compute_sig_hash` to elide only `[sig_type][sig_payload]`. Prefix is covered.
  - Pro: extensible for future protocol-visible VERIFY data.
  - Con: every default-code impl updates to skip prefix; conflicts with existing `signature_type` byte; bigger consensus surface.
- **A2.** Envelope field `nonce_key: uint256`; `tx.nonce` stays as the sequence. Consensus check: `tx.nonce == state[tx.sender].nonces[tx.nonce_key]`.
  - Pro: covered by existing sighash for free.
  - Pro: one RLP field, no VERIFY-layout change, no signature-type conflict.
  - Pro: matches Tempo.
  - Con: violates the earlier "no envelope changes" stance.

**Pick: A2.** The earlier stance was aesthetic, not principled. One envelope field is cheaper than a VERIFY-layout restructure plus a sighash rule change.

**Implication for 2D nonces:** add `nonce_key: uint256` as an envelope field; drop any frame-prefix encoding.

## Class B binding: delegation bundle

No sighash change needed. Binding chain:

1. **Delegator authority.** Delegator signs an offchain canonical digest:
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
   Self-contained, independent of any specific tx.

2. **Authority proof.** Manager calls `delegator.validateAuth(delegationDigest, proof)`. The account verifies under whatever scheme it uses. No tx sighash involved.

3. **Action binding.** Caveats inspect the tx's SENDER frame content (targets, values, call data). SENDER frames are **not** elided from the tx sighash, so the actions they describe are signed by the delegate. Caveats reading them are reading signed data.

4. **Replay protection.** `salt` + `expiry` in the delegation digest, plus manager-side nonce tracking.

What binds a specific redemption to a specific tx: the caveats evaluating signed SENDER frames. If a spend-limit caveat reads that SENDER frame 1 calls `USDC.transfer(X, 10e6)`, the caveat is reading content covered by the tx sighash.

**Implication for permissions:** no sighash change, no tx-sighash binding of the bundle. But `manager.isAuthorized` must receive the SENDER frames (or a canonical hash) as an argument so caveats can evaluate signed action content. This is a protocol affordance on default code: it must be able to pass the signed portion of the tx to the manager.

## Protocol affordances required

For Class A (2D nonces, design A2):
- One new envelope field `nonce_key: uint256`.
- Protocol nonce check updated.
- No sighash rule change. No VERIFY-layout change.

For Class B (permissions):
- Default code must access the list of SENDER frames (or a canonical commitment) in tx-scoped context, sufficient to pass into `manager.isAuthorized`.
- That data is already covered by the tx sighash (SENDER frames are not elided).
- No sighash rule change. No envelope field.

## Summary

| Proposal | Class | Binding | Sighash change? | Envelope change? |
|---|---|---|---|---|
| 2D nonces | A | Envelope `nonce_key`, covered by existing sighash | No | Yes, one field |
| Permissions | B | Delegator's independent digest + caveats inspecting signed SENDER frames | No | No |

The earlier "no envelope changes anywhere" stance was wrong. 2D nonces warrant one envelope field because no account-side signature can bind the stream key. Permissions does not warrant one because the delegation has its own independent signature chain.

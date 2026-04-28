# EIP-8141 Primitive: Sighash Binding for Protocol-Visible Frame Data

```
Canonical for:  Class A vs Class B binding analysis
Referenced by:  P1.N, P1.W, P1.NS, P1.NSW; P2
```

_Cross-cutting binding analysis; relevant to any Phase-1 alternative that adds protocol-visible data, and to Phase-2 permissions._

## Problem

EIP-8141's `compute_sig_hash` elides VERIFY frame data. This is load-bearing: the default-code signature lives in VERIFY calldata, so it cannot be part of its own hash.

Earlier 2D-nonces drafts placed protocol-visible data inside VERIFY calldata (a 40-byte `(nonce_key, nonce_seq)` prefix). The elision means none of it is bound by the transaction signature — an attacker with the signed bytes could rewrite the prefix and still produce a valid `tx.signature`. Correctness bug, not a style concern.

This doc resolves the binding for protocol-visible data added by Phase-1 (and forward-looking Phase-2) features.

## Two classes of protocol-visible data

### Class A: validity depends only on the transaction

Stream key and sequence for 2D nonces; validity window bounds. No account-side signature covers them; the consensus check happens before any account code runs. If the tx signature doesn't cover the field, nothing does. **Class A must be bound by the tx sighash.**

### Class B: validity depends on an independent account-side signature

Forward-looking: a Phase-2 delegation bundle. The delegator signs a canonical digest offchain (never in the tx); a manager verifies that signature via `validateAuth`. **Class B does not require tx-sighash coverage.** Integrity comes from the account-side signature over a self-contained digest.

Conflating the classes is what led earlier drafts to put everything in VERIFY calldata and claim no sighash changes were needed.

## Class A binding: 2D nonces and validity windows

Two viable designs were considered for 2D nonces:

- **A1.** Structured VERIFY layout: `VERIFY.data = [protocol_prefix][sig_type][sig_payload]`. Change `compute_sig_hash` to elide only `[sig_type][sig_payload]`. Prefix is covered.
  - Pro: extensible for future protocol-visible VERIFY data.
  - Con: every default-code impl updates to skip prefix; conflicts with existing `signature_type` byte; bigger consensus surface.
- **A2.** Envelope field `nonce_key: uint256`; `tx.nonce` stays as the sequence. Consensus check: `tx.nonce == NonceLaneRegistry.get(tx.sender, tx.nonce_key)`.
  - Pro: covered by existing sighash for free.
  - Pro: one RLP field, no VERIFY-layout change, no signature-type conflict.
  - Pro: matches Tempo.

**Pick: A2.** One envelope field is cheaper than a VERIFY-layout restructure plus a sighash rule change.

Validity-window bounds (`valid_after`, `valid_before`) are envelope fields by the same reasoning: the tx-sighash covers them automatically; consensus checks them pre-frame.

**Implication for the Phase-1 alternatives:** all stream-key, sequence, and time-bound data lives in envelope fields. No VERIFY-layout restructure. No sighash rule change.

### Signer binding is a non-Class-A case

Signer binding claims `(digest, address)` ahead of `ECRECOVER` execution. The claim's integrity is provided by the PQ-signature-over-pubkey check at VERIFY time, not by tx-sighash binding. The digest sits in VERIFY data and is elided; that's fine because the binding is `signature(digest, sk) verifies under pk(account)`. No envelope field needed.

## Class B binding: forward-looking delegation

The Phase-2 permissions proposal ([`phase-2/permissions.md`](../phase-2/permissions.md)) introduces a delegation bundle. Binding chain:

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

**Implication for Phase-2 permissions:** no sighash change, no tx-sighash binding of the bundle. But the manager must receive the SENDER frames (or a canonical hash) as an argument so caveats can evaluate signed action content. This is a protocol affordance on default code, applicable when permissions ships as a follow-on upgrade. Out of scope for Phase 1.

## Protocol affordances required

For Class A (2D nonces, validity windows; Phase-1 alternatives):
- Envelope fields `nonce_key`, `valid_after`, `valid_before`.
- Protocol pre-tx checks updated.
- No sighash rule change. No VERIFY-layout change.

For Class B (Phase-2 permissions, future):
- Default code must access the list of SENDER frames (or a canonical commitment) in tx-scoped context, sufficient to pass into a manager call.
- That data is already covered by the tx sighash (SENDER frames are not elided).
- No sighash rule change. No envelope field.

## Summary

| Data | Class | Binding | Sighash change? | Envelope change? |
|---|---|---|---|---|
| 2D-nonce key | A | Envelope `nonce_key`, covered by existing sighash | No | Yes, one field |
| Validity bounds | A | Envelope `valid_after` / `valid_before`, covered by existing sighash | No | Yes, two fields |
| Signer binding `(digest, address)` claim | n/a | PQ signature over pubkey at VERIFY time | No | No |
| Delegation bundle (Phase 2) | B | Delegator's independent digest + caveats inspecting signed SENDER frames | No | No |

The earlier "no envelope changes anywhere" stance was wrong. Stream keys and time bounds warrant envelope fields because no account-side signature can bind them. Signer-binding claims and delegation bundles do not, because they have their own independent signature chains.

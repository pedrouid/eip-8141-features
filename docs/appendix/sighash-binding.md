# EIP-8141 Primitive: Sighash Binding for Protocol-Visible Frame Data

```
Canonical for:  Class A vs Class B binding analysis
Referenced by:  Flexible nonces, Key streams (consolidated EIP); Envelope expiry / Auth scopes (comparison only)
```

_Cross-cutting binding analysis; relevant to any alternative that adds protocol-visible data._

## Problem

EIP-8141's `compute_sig_hash` elides VERIFY frame data. This is load-bearing: the default-code signature lives in VERIFY calldata, so it cannot be part of its own hash.

Earlier Flexible-nonces drafts placed protocol-visible data inside VERIFY calldata (a 40-byte `(nonce_key, nonce)` prefix). The elision means none of it is bound by the transaction signature; an attacker with the signed bytes could rewrite the prefix and still produce a valid `tx.signature`. Correctness bug, not a style concern.

This doc resolves the binding for protocol-visible data added by the proposals.

## Two classes of protocol-visible data

### Class A: validity depends only on the transaction

Stream key and sequence for Flexible nonces; deadlines. No account-side signature covers them; the consensus check happens before any account code runs. If the tx signature doesn't cover the field, nothing does. **Class A must be bound by the tx sighash.**

Deadlines, in particular, are now carried by the upstream expiry verifier frame as the 8-byte `frame.data` of a special `VERIFY` frame whose target is `EXPIRY_VERIFIER = address(0x8141)`. That frame's `data` is exempted from VERIFY-data elision in `compute_sig_hash`, so the deadline is sighash-covered for free without adding an envelope field. The Class A constraint is satisfied; the binding mechanism is a sighash-rule carve-out rather than a new envelope slot.

### Class B: validity depends on an independent signature chain

Signer-binding claims fall here. The integrity of a `(digest, address)` claim comes from the PQ-signature-over-pubkey check at VERIFY time, not from tx-sighash coverage. **Class B does not require tx-sighash coverage.** Integrity comes from the independent signature.

Conflating the classes is what led earlier drafts to put everything in VERIFY calldata and claim no sighash changes were needed.

## Class A binding: Flexible nonces and deadlines

Two viable designs were considered for Flexible nonces:

- **A1.** Structured VERIFY layout: `VERIFY.data = [protocol_prefix][sig_type][sig_payload]`. Change `compute_sig_hash` to elide only `[sig_type][sig_payload]`. Prefix is covered.
  - Pro: extensible for future protocol-visible VERIFY data.
  - Con: every default-code impl updates to skip prefix; conflicts with existing `signature_type` byte; bigger consensus surface.
- **A2.** Envelope stream selector (`nonce_key: uint256` standalone, `signer: uint64` aggregated); `tx.nonce` stays as the sequence. Consensus check: `tx.nonce == NonceManager.get(tx.sender, tx.nonce_key)` standalone or `tx.nonce == AuthManager.getNonce(tx.sender, tx.signer)` aggregated.
  - Pro: covered by existing sighash for free.
  - Pro: one RLP field, no VERIFY-layout change, no signature-type conflict.
  - Pro: matches Tempo.

**Pick: A2.** One envelope field is cheaper than a VERIFY-layout restructure plus a sighash rule change.

Deadlines follow a different binding path. The upstream-merged expiry verifier frame carries the deadline as `frame.data` of a special `VERIFY` frame; `compute_sig_hash` is rewritten to elide every VERIFY frame's data *except* the expiry verifier frame's. This is a targeted carve-out, not a generic VERIFY-layout restructure, and it leaves all other default-code semantics unchanged. The consolidated EIP uses this mechanism; the Envelope-expiry alternative kept under [`proposals/envelope-expiry.md`](../proposals/envelope-expiry.md) explored the A2-style envelope-field approach for deadlines and is preserved as comparison surface.

**Implication for the alternatives:** stream-key and sequence data lives in envelope fields (A2). Deadlines live in the upstream expiry verifier frame's `frame.data`, sighash-covered via the `frame.target == EXPIRY_VERIFIER` carve-out.

## Class B binding: signer binding

Signer binding claims `(digest, address)` ahead of `ECRECOVER` execution. The claim's integrity is provided by the PQ-signature-over-pubkey check at VERIFY time, not by tx-sighash binding. The digest sits in VERIFY data and is elided; that's fine because the binding is `signature(digest, sk) verifies under pk(account)`. No envelope field needed.

## Protocol affordances required

For Class A (Flexible nonces, deadlines):
- Envelope field for the stream selector: `nonce_key` (standalone) or `signer` (aggregated).
- Pre-frame consensus nonce check updated.
- For deadlines: the upstream expiry verifier frame at `EXPIRY_VERIFIER = address(0x8141)` (already merged into the baseline). `compute_sig_hash` exempts that frame from VERIFY-data elision so the deadline is sighash-covered.
- No new envelope field for deadlines. No further sighash rule change beyond the upstream carve-out.

For Class B (signer binding):
- PQ verification at VERIFY time, with pubkey resolved from `PubkeyRegistry`.
- No sighash rule change. No envelope field.

## Summary

| Data | Class | Binding | Sighash change? | Envelope change? |
|---|---|---|---|---|
| Flexible-nonce stream selector | A | Envelope `nonce_key` (standalone) / `signer` (aggregated), covered by existing sighash | No | Yes, one field |
| Deadline | A | `frame.data` of the upstream expiry verifier frame, covered by the existing carve-out in `compute_sig_hash` | Upstream-merged carve-out, not added by this proposal | No |
| Signer binding `(digest, address)` claim | B | PQ signature over pubkey at VERIFY time | No | No |

The earlier "no envelope changes anywhere" stance was wrong for stream keys: they warrant an envelope field because no account-side signature can bind them. Deadlines no longer require an envelope field either, because the upstream verifier-frame carve-out provides the same Class A coverage at lower cost. Signer-binding claims have their own independent signature chain, so they need neither.

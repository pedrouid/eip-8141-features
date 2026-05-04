# EIP-8141 Primitive: Sighash Binding for Protocol-Visible Frame Data

```
Canonical for:  Class A vs Class B binding analysis
Referenced by:  N, W, NS, NSW
```

_Cross-cutting binding analysis; relevant to any alternative that adds protocol-visible data._

## Problem

EIP-8141's `compute_sig_hash` elides VERIFY frame data. This is load-bearing: the default-code signature lives in VERIFY calldata, so it cannot be part of its own hash.

Earlier Flexible-nonces drafts placed protocol-visible data inside VERIFY calldata (a 40-byte `(nonce_key, nonce_seq)` prefix). The elision means none of it is bound by the transaction signature; an attacker with the signed bytes could rewrite the prefix and still produce a valid `tx.signature`. Correctness bug, not a style concern.

This doc resolves the binding for protocol-visible data added by the proposals.

## Two classes of protocol-visible data

### Class A: validity depends only on the transaction

Stream key and sequence for Flexible nonces; validity window bounds. No account-side signature covers them; the consensus check happens before any account code runs. If the tx signature doesn't cover the field, nothing does. **Class A must be bound by the tx sighash.**

### Class B: validity depends on an independent signature chain

Signer-binding claims fall here. The integrity of a `(digest, address)` claim comes from the PQ-signature-over-pubkey check at VERIFY time, not from tx-sighash coverage. **Class B does not require tx-sighash coverage.** Integrity comes from the independent signature.

Conflating the classes is what led earlier drafts to put everything in VERIFY calldata and claim no sighash changes were needed.

## Class A binding: Flexible nonces and validity windows

Two viable designs were considered for Flexible nonces:

- **A1.** Structured VERIFY layout: `VERIFY.data = [protocol_prefix][sig_type][sig_payload]`. Change `compute_sig_hash` to elide only `[sig_type][sig_payload]`. Prefix is covered.
  - Pro: extensible for future protocol-visible VERIFY data.
  - Con: every default-code impl updates to skip prefix; conflicts with existing `signature_type` byte; bigger consensus surface.
- **A2.** Envelope field `nonce_key: uint256`; `tx.nonce` stays as the sequence. Consensus check: `tx.nonce == NonceLaneRegistry.get(tx.sender, tx.nonce_key)`.
  - Pro: covered by existing sighash for free.
  - Pro: one RLP field, no VERIFY-layout change, no signature-type conflict.
  - Pro: matches Tempo.

**Pick: A2.** One envelope field is cheaper than a VERIFY-layout restructure plus a sighash rule change.

Validity-window bounds (`valid_after`, `valid_before`) are envelope fields by the same reasoning: the tx-sighash covers them automatically; consensus checks them pre-frame.

**Implication for the alternatives:** all stream-key, sequence, and time-bound data lives in envelope fields. No VERIFY-layout restructure. No sighash rule change.

## Class B binding: signer binding

Signer binding claims `(digest, address)` ahead of `ECRECOVER` execution. The claim's integrity is provided by the PQ-signature-over-pubkey check at VERIFY time, not by tx-sighash binding. The digest sits in VERIFY data and is elided; that's fine because the binding is `signature(digest, sk) verifies under pk(account)`. No envelope field needed.

## Protocol affordances required

For Class A (Flexible nonces, validity windows):
- Envelope fields `nonce_key`, `valid_after`, `valid_before`.
- Protocol pre-tx checks updated.
- No sighash rule change. No VERIFY-layout change.

For Class B (signer binding):
- PQ verification at VERIFY time, with pubkey resolved from `PubkeyRegistry`.
- No sighash rule change. No envelope field.

## Summary

| Data | Class | Binding | Sighash change? | Envelope change? |
|---|---|---|---|---|
| Flexible-nonce key | A | Envelope `nonce_key`, covered by existing sighash | No | Yes, one field |
| Validity bounds | A | Envelope `valid_after` / `valid_before`, covered by existing sighash | No | Yes, two fields |
| Signer binding `(digest, address)` claim | B | PQ signature over pubkey at VERIFY time | No | No |

The earlier "no envelope changes anywhere" stance was wrong. Stream keys and time bounds warrant envelope fields because no account-side signature can bind them. Signer-binding claims do not, because they have their own independent signature chain.

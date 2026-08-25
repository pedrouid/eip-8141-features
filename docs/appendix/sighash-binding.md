# Signature-Hash Binding

## Current rule

Current EIP-8141 computes one canonical hash over the full transaction. Raw signature bytes are elided only for signature entries whose `msg` is empty. Frame data, frame gas limits, flags, targets, fees, and signature metadata remain covered.

This removes the circularity that motivated the stale `compute_frame_sig_hash` extension. Sender, payer, and guarantor may each carry an empty-`msg` signature entry and independently sign the same canonical hash.

## Bound surfaces

| Surface | Binding source |
|---|---|
| Sender authorization | Empty-`msg` signature over canonical hash, or account-defined equivalent |
| Guarantor authorization | Empty-`msg` protocol signature selected by canonical paymaster |
| EIP-8141 nonce keys and sequence | Canonical transaction payload |
| Expiry deadline | Expiry verifier frame data, covered as ordinary frame data |
| Signer-binding digest | Application signature/witness verified by account code |
| Nonceless replay identifier | Separate fee- and raw-signature-invariant logical hash |

## Application digest distinction

A signer-binding frame authorizes an application digest such as an ERC-2612 permit hash. The canonical transaction hash commits to the frame and signature metadata but does not prove that the account intended the returned application digest. Account code must verify that digest directly under its chosen signature or policy.

## Guarantor replay distinction

Canonical-hash coverage prevents mutation of sender validation or the required `bumpNonce` frame after the guarantor signs. It does not replace the paymaster's replay nonce when sender authentication fails, because the sender's selected nonce set is intentionally not consumed on that path.

## Nonceless distinction

The canonical hash includes fees and may include some raw signature bytes, so it cannot identify one logical nonceless transaction across fee bumps or re-signing. Native nonceless mode therefore defines a separate replay identifier while continuing to use the canonical hash for authorization.

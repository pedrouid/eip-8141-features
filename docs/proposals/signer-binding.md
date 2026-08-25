# Signer Binding for EIP-8141

_Individual alternative and part of the consolidated draft._

## Problem

EIP-8141's signature list lets new account code consume secp256k1, P256, or `ARBITRARY` witnesses. Existing immutable contracts still call `ECRECOVER(digest, v, r, s)` and compare the result with an owner address. Without a compatibility path, non-secp256k1 accounts cannot use those contracts' permit and meta-transaction surfaces.

## Single-line delta

A standalone `VERIFY` frame marked `SIGNER_BINDING_FLAG` returns application digests authorized by its target account. The protocol stores `digest -> target` for the transaction. `ECRECOVER` checks this table before its unchanged secp256k1 path.

## Normative shape

- `SIGNER_BINDING_FLAG = 0x10`.
- A binding frame must use `VERIFY`, have an explicit non-null target, and carry no approval scope.
- The frame executes account code under normal `VERIFY` restrictions.
- Successful return data is a non-empty concatenation of 32-byte digests.
- Each digest binds to `frame.target`.
- Duplicate pairs are no-ops; same-digest conflicts revert.
- `MAX_BOUND_SIGNERS = 8` caps unique entries.
- The table is cleared at transaction entry and discarded at transaction exit.

## Authorization sources

The account decides how to authorize each digest:

- a protocol-validated P256 or secp256k1 entry can be inspected with `SIGPARAM`;
- a post-quantum or other custom witness can be read from an `ARBITRARY` entry with `SIGDATACOPY`;
- account storage, delegation, recovery policy, or multiple signatures may participate under ordinary account code.

No protocol pubkey registry is required. Large public keys can remain in transaction witness data or use a future EIP-8141 public-key-alias extension. This follows EIP-8130's useful separation: protocol state identifies authority, while scheme-specific public material need not occupy persistent slots.

## Modified `ECRECOVER`

```python
if digest in verified_signers:
    return verified_signers[digest]
return existing_secp256k1_recover(digest, v, r, s)
```

On a hit, `v`, `r`, and `s` are ignored. On a miss, behavior is byte-for-byte unchanged. The precompile keeps its existing gas price.

## Mempool

Binding frames normally appear after payer approval and are outside the public validation prefix. Their success remains consensus-critical. A guarantor does not turn binding failure into a tolerated sender-validation failure because the binding frame has no `APPROVE_EXECUTION` scope.

## Wallet flow

For an ERC-2612 permit:

1. include the permit digest and authorization as a signature entry;
2. run a binding frame against the owner account;
3. return the permit digest after verification;
4. call `permit` in a `SENDER` frame with placeholder `v`, `r`, and `s`;
5. the token's existing `ECRECOVER` call resolves to the bound owner.

Wallets must display the digest, target account, and downstream contract/action before requesting authorization.

## Security

Returning a digest grants legacy-signature recognition for the remainder of the transaction. Account code must authenticate the application digest itself and must not infer authorization merely from the transaction's canonical hash. The cap and conflict rule prevent unbounded or ambiguous table population.

# Verified-Signers Table and Modified ECRECOVER

```
Canonical for:  verified-signers table, modified ECRECOVER (hit-path-first lookup)
Referenced by:  Signer binding, Key lanes, Authorization scopes
```

_Canonical specification of the tx-scoped verified-signers table and the modified `ECRECOVER` semantics that back **signer binding**. Single source of truth referenced by [`signer-binding.md`](../proposals/signer-binding.md), [`key-lanes.md`](../proposals/key-lanes.md), and [`authorization-scopes.md`](../proposals/authorization-scopes.md). Background and registry state in [`appendix/system-contracts.md`](system-contracts.md) and [`appendix/pq-analysis.md`](pq-analysis.md)._

## Why signer binding exists

EIP-8141's tx-level authentication is PQ-flexible via the VERIFY-frame `signature_type` byte. But immutable contracts that call `ECRECOVER` on an application digest (ERC-2612 `permit`, WETH, raw `ecrecover`) derive the signer from a secp256k1 signature and cannot be redeployed. PQ accounts are locked out of every existing `ECRECOVER` caller.

Signer binding threads the needle: a PQ VERIFY frame *proves* `(digest, address)` ahead of execution, and `ECRECOVER` looks the answer up. The 0x01 ABI keeps returning an address. The recovery step is replaced by a table consult populated from `verify(pk, msg, sig)` in a prior frame. Immutable contracts continue to work without redesign.

## Tx-scoped verified-signers table

```
table: set[(digest32, address)]
```

Lifecycle:

1. **Cleared** at tx entry (alongside other tx-scoped state).
2. **Populated** during VERIFY-frame execution.
3. **Queried** during SENDER-frame execution by any `ECRECOVER` call.

Per-tx cap: `MAX_BOUND_SIGNERS = 8`. Bounds table-population cost; matches approve + swap + repay redemption shapes.

## Population rule

A VERIFY frame binds a `(digest, address)` pair iff all of:

1. `signature_type != 0x0` (secp256k1 needs no binding).
2. `frame.data` carries a 32-byte application digest (after `signature_type`) followed by the PQ signature.
3. The signature verifies under the declared scheme using the pubkey resolved from `PubkeyRegistry.get(frame.target)` (see [`appendix/system-contracts.md`](system-contracts.md)), bound to `frame.target` by the scheme's address rule.
4. The frame calls `APPROVE`.

Multiple bindings per frame are allowed, up to the per-tx cap. Entries are write-once: a second insert with the same `(digest, address)` is a no-op; a conflict (same digest, different address) reverts the frame.

## Modified ECRECOVER

```
ECRECOVER(digest, v, r, s):
    if (digest, addr) in tx.verified_signers:
        return addr                                  // bound-signer hit
    return existing_secp256k1_recover(digest, v, r, s) // unchanged; EIP-8151 still applies
```

- Hit-path cost: 3000 gas (constant-time table lookup; cheaper than an EC operation).
- On hit, `(v, r, s)` are unconstrained; wallets pass zeros.
- Miss-path is byte-identical to today.

## Mempool admission

Restrictive-tier admissible: pubkey resolution is one storage slot read against `PubkeyRegistry`'s `storageRoot`. The 100 000 validation-prefix gas cap absorbs PQ verification once stage-2 PQ precompiles ship. Before then, signer-binding txs route through the expansive tier. See [`appendix/mempool-tiers.md`](mempool-tiers.md).

The verified-signers table is rebuilt per-tx; RBF and block-invalidation rules are unchanged.

Sighash binding: in-frame digest claims sit inside VERIFY data, elided as today. The integrity of a binding claim comes from the PQ-signature-over-pubkey check at VERIFY time, not from tx-sighash binding. See [`appendix/sighash-binding.md`](sighash-binding.md) for the full reasoning.

## Composition

- **EIP-8151**: complementary. EIP-8151 zeros revoked-secp256k1-key recovery; signer binding provides the positive PQ path for the same address. A revoked-secp256k1 account with a registered PQ pubkey resolves only via signer binding; un-bound digests return zero.
- **EIP-8164**: complementary. EIP-8164 reserves an address space rooted in a PQ pubkey hash; signer binding lets that address be recognized by immutable `ECRECOVER` callers.

## Wallet UX

Wallets surface "this tx will let `<contract>` recognize you as `<address>` via `permit`" before signing. Hardware wallets parse the `PubkeyRegistry` registration tx natively as a one-time onboarding step. First-use registration is a one-time SSTORE-from-zero cost.

Permit composition: the wallet adds a binding VERIFY frame whose `digest` matches the EIP-712 hash the contract recomputes; the SENDER frame calls `permit(...)` normally; the contract's internal `ecrecover` resolves via the bound entry.

## Non-goals

- Block-builder aggregation (defer to PQ stage 2).
- Cross-tx binding (would expand replay surface).
- Non-32-byte digests.
- Rotation outside `PubkeyRegistry.register` + `clear`.
- Inline envelope pubkeys (see [`appendix/system-contracts.md`](system-contracts.md) and [`appendix/pq-analysis.md`](pq-analysis.md)).

## Spec delta summary

1. Tx-scoped verified-signers table cleared at tx entry, populated during VERIFY, queried during SENDER.
2. Population rule (four conditions above).
3. `ECRECOVER` extended with hit-path-first lookup; miss-path byte-identical.
4. `MAX_BOUND_SIGNERS = 8`.
5. Restrictive-tier admission via one slot read on `PubkeyRegistry`.

**Zero new envelope fields, zero new opcodes, zero new precompiles, zero account-encoding changes, zero sighash changes.**

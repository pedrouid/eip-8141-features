# Proposal Overview

## Rebased architecture

The consolidated EIP-8141 owns the transaction signature list, protocol signature validation, signature introspection, native sequenced and nonceless nonce modes, two-dimensional gas, static batch constraints, and the expiry verifier. EIP-8250 and EIP-8130 supply replay-design provenance, while [EIP-8164](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md) motivates alternative-key interoperability with existing contracts. None is a separate ownership boundary for these EIP-8141 mechanisms.

| Proposal | Outcome | Status |
|---|---|---|
| [Flexible nonces](proposals/flexible-nonces.md) | Parallel replay domains | Consolidated draft |
| [Signer binding](proposals/signer-binding.md) | Existing `ECRECOVER` contracts recognize account-defined schemes | Consolidated draft |
| [Key streams](proposals/key-streams.md) | Flexible nonces + signer binding | Viable bundle |
| [Nonceless transactions](proposals/nonceless-transactions.md) | Counter-free short-lived replay protection | Consolidated draft; activation values pending |
| [Auth scopes](proposals/auth-scopes.md) | Maximum bundle | Consolidated draft |
| [Envelope expiry](proposals/envelope-expiry.md) | One-sided envelope deadline | Superseded by expiry verifier |
| [Validity windows](proposals/validity-windows.md) | Scheduled activation + deadline | Comparison only |

Guarantors are cross-cutting and live in the consolidated draft plus [`appendix/guarantors.md`](appendix/guarantors.md).

## What was removed

### Single `signer` envelope field

The old field combined signer identity and nonce selection. It lost the multi-key/nullifier outcome and prevented replay domains from surviving signer rotation. Native EIP-8141 nonce keys now remain independent from authorization.

### `AuthManager`

Its nonce role is superseded by EIP-8141's `NONCE_MANAGER`. Its pubkey role is unnecessary because EIP-8141 exposes protocol signature metadata and arbitrary witnesses to account code. Removing it also avoids permanent large-pubkey storage.

### Frame signature hash

The current canonical signature hash covers all frames and elides raw signatures whose `msg` is empty. Sender and guarantor can independently sign the same transaction without a second hash function.

### Envelope deadlines

The expiry verifier frame already provides a signed, deterministic deadline. Nonceless mode reuses it and adds only a bounded maximum window.

## Consolidated draft

`EIPS/eip-8141.md` is current upstream EIP-8141 plus:

- `nonce_keys`, `nonce_seq`, `NONCE_MANAGER`, atomic payment-time consumption, state-gas pricing, and keyed mempool identity;
- `[NONCE_KEY_MAX]`, bounded expiry, logical replay identity, `NONCELESS_REPLAY_MANAGER`, and nonceless replacement rules;
- `APPROVE_GUARANTEE`, guarantor context, tolerated sender-validation failure, payer override, public-mempool prefix, and canonical paymaster replay fallback;
- `SIGNER_BINDING_FLAG`, return-data digest binding, an eight-entry transaction table, and the `ECRECOVER` hit path.

## Open questions

- Can the canonical paymaster's guarantor replay path be reduced further without allowing guarantor grief or sender nonce-set advancement?
- Should signer binding reuse the existing precompile gas price on the hit path or define a lower fixed price?
- What L1 throughput and expiry assumptions produce defensible nonceless replay-buffer parameters?

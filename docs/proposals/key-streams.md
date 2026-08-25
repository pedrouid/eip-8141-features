# Key Streams

_Canonical bundle: native keyed nonce sets plus signer binding._

## Outcome

Key streams preserve two independent properties inside EIP-8141:

1. replay independence through native nonce-key sets;
2. legacy-contract interoperability through transaction-scoped signer binding.

The stale design forced both through one `uint64 signer` and one `AuthManager`. The consolidated design keeps nonce selection independent from authorization. A transaction can select a replay-domain set without requiring that set to identify a particular signing key.

## Components

- [`flexible-nonces.md`](flexible-nonces.md): native nonce payload, state, and consumption.
- [`signer-binding.md`](signer-binding.md): return-data binding frames and `ECRECOVER` compatibility.
- [`../appendix/verified-signers.md`](../appendix/verified-signers.md): table invariants.
- [`../appendix/mempool-tiers.md`](../appendix/mempool-tiers.md): public, expansive, and private admission boundaries.

## Why decoupling is better

- Sets of up to 16 full-width keys support nullifier-derived domains.
- One account authorization can atomically advance several replay domains.
- One nonce domain can survive signer rotation or threshold-policy changes.
- EIP-8141's signature list already carries scheme and signer metadata.
- Binding verification belongs to account code, avoiding permanent storage of large public keys.

## Integration rules

- Sender-authorized payment consumes the selected EIP-8141 nonce set.
- Failed guarantor-backed sender validation consumes no sender key; the guarantor paymaster advances its own replay nonce.
- Binding frames never approve execution, payment, or guarantee scope.
- Nonceless `[NONCE_KEY_MAX]` is a native counter-free mode; it never aliases a sequenced key.

## Protocol surface

The combined surface is `nonce_keys`, `nonce_seq`, `NONCE_MANAGER`, `NONCELESS_REPLAY_MANAGER`, `SIGNER_BINDING_FLAG`, the `verified_signers` table, and the `ECRECOVER` hit path. It adds no `AuthManager`, pubkey registry, opcode, precompile, or account-encoding field.

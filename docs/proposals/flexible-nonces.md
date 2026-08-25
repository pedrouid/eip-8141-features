# Flexible Nonces

_Canonical component of the consolidated EIP-8141 draft._

## Position

Parallel nonce domains belong to EIP-8141 itself. The stale draft used one `uint64 signer` field and tied every non-zero stream to a registered signer in `AuthManager`. The consolidated design instead integrates the stronger ordered key-set mechanics developed in [EIP-8250](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8250.md).

## Transaction shape

EIP-8141 replaces its scalar `nonce` with:

```text
nonce_keys: list[uint256]
nonce_seq: uint64
```

- `[0]` aliases the legacy account nonce.
- `[NONCE_KEY_MAX]` selects nonceless mode with sequence zero, bounded expiry, and consensus replay-ID storage.
- A strictly increasing list of 1 to 16 non-zero keys selects protocol-managed sequences in EIP-8141's `NONCE_MANAGER`.
- Every selected key must equal the shared `nonce_seq` before frame execution.
- Sender-authorized payment approval advances every selected key atomically.
- Non-overlapping non-zero key sets are replay-independent.

The multi-key form supports privacy nullifiers and capabilities that must atomically mark several replay domains. Nonce selection remains independent from signer identity, so key rotation does not change replay domains.

## State-gas integration

First use of a non-zero key creates one 64-byte storage slot and charges:

```text
STATE_BYTES_PER_STORAGE_SET * CPSB = 64 * 1,530 = 97,920 state gas
```

The charge comes from the payment-approving frame's state-gas pool. Existing slots add no durable bytes and incur no state-gas charge. This replaces EIP-8250's older execution-gas surcharge with the current EIP-8141/EIP-8037 accounting model.

## Composition

- Failed guarantor-backed sender validation consumes no sender key. The canonical paymaster advances its own replay nonce instead.
- Signer binding is orthogonal: account code may authorize any key set using any supported signature scheme.
- Nonceless transactions reserve `[NONCE_KEY_MAX]` natively and never access a sequenced nonce slot.

## Mempool boundary

The public mempool still admits at most one frame transaction per sender. Disjoint key sets remove the protocol replay dependency but not shared sender balance, payer balance, or validation-state invalidators. Concurrent admission remains blocked on explicit exposure bounds.

## Non-goals

- No `AuthManager` registry.
- No width reduction from `uint256` keys.
- No implicit coupling between a nonce key and a signature entry.
- No claim that disjoint replay domains imply fully independent transaction validity.

# Nonceless Transactions

_Integrated into the consolidated EIP-8141 draft. Derived from EIP-8130's bounded replay model._

## Outcome

Nonceless transactions are a native EIP-8141 nonce mode, not a companion EIP. They remove counter coordination without removing replay protection.

```text
nonce_keys = [NONCE_KEY_MAX]
nonce_seq = 0
NONCE_KEY_MAX = 2**256 - 1
```

The sentinel is permanently reserved. It never reads or increments a `NONCE_MANAGER` slot and cannot appear in a mixed key set.

## Bounded validity

The first frame must be the canonical EIP-8141 expiry verifier. Its deadline must be strictly in the future and no farther away than `NONCELESS_EXPIRY_WINDOW`.

The expiry window is consensus configuration, not local mempool policy. Its L1 value remains an explicit Draft activation gate pending worst-case throughput benchmarks.

## Logical replay identity

`nonceless_replay_id` commits to the chain, sender, each frame's mode, flags, target, value and data, expiry, signature metadata, explicit signed messages, and blob hashes. It excludes:

- the fixed nonceless nonce marker and zero sequence;
- fee fields;
- frame execution and state-gas limits; and
- raw signature bytes.

Fee, gas-budget, and signature variants are therefore replacements of the same logical transaction, but each variant must independently pass EIP-8141 signature and frame validation. Changing a call, target, value, deadline, signer identity, explicit signed message, or blob hash creates a new replay ID. The full transaction hash is never used for nonceless replay protection.

## Consensus replay state

EIP-8141 installs a separate `NONCELESS_REPLAY_MANAGER` system account. Its domain-separated storage contains:

```text
seen[(sender, replay_id)] -> expiry
ring[index] -> (sender, replay_id, expiry)
cursor -> encoded next index
```

Before frames execute, consensus rejects a live duplicate or a live entry at the current ring slot. The latter is the safe full-buffer condition. Successful payment approval inserts the replay record atomically; guarantor approval alone does not.

Each ring entry uses two slots, the live map uses one, and the cursor uses one. At most four zero slots become non-zero in one insertion:

```text
NONCELESS_MAX_STATE_GAS
  = 4 * STATE_BYTES_PER_STORAGE_SET * CPSB
  = 391,680
```

The ring and live map are ordinary consensus state. They roll back deterministically on reorgs. Stale entries are cleared only when their ring slot is reused, and a stale entry never deletes a later reuse of the same replay ID.

## Mempool and guarantors

- Pending identity is `(sender, nonceless_replay_id)`.
- Fee and gas-budget bumps follow the normal EIP-8141 replacement rule.
- Builders cannot include the same identity twice because the second transaction fails the consensus live-map check.
- Nodes evict the transaction at its deadline and revalidate when the current ring slot changes.
- On successful sender authentication, the canonical guarantor settlement frame reserves `391,680` state gas and records the replay ID through `APPROVE_PAYMENT`.
- On failed sender authentication, no sender replay state is consumed; the paymaster advances `guarantor_nonce` instead.

## Remaining activation gate

The semantics, storage layout, gas ownership, guarantor interaction, and reorg behavior are now specified in EIP-8141. Two coupled L1 values remain to be benchmarked and fixed before the draft can advance:

1. `NONCELESS_EXPIRY_WINDOW`
2. `REPLAY_BUFFER_CAPACITY`

The capacity must cover the maximum number of nonceless transactions consensus can accept during the expiry window. If it does not, safety is preserved by full-buffer rejection, but availability is unnecessarily constrained.

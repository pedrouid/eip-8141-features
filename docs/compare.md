# Current EIP-8141 vs Upgraded EIP-8141 vs EIP-8130

_Comparison for the consolidated draft in `EIPS/eip-8141.md`._

## Baseline

“Current EIP-8141” means upstream commit `15bc93fd` (August 24, 2026). All three specifications remain Draft.

Current EIP-8141 already includes frame execution, a signature list, secp256k1/P256/`ARBITRARY` entries, signature introspection, per-frame execution and state gas, atomic batches, the expiry verifier, blob support, and restrictive public-mempool rules.

The upgrade adds native keyed and nonceless replay modes, guarantor payment, and transaction-scoped signer binding directly to EIP-8141.

## Executive judgment

Current EIP-8141 is an **execution-first** abstraction: accounts remain arbitrary code, while the protocol standardizes validation, payment, execution frames, and gas isolation.

Upgraded EIP-8141 preserves that boundary. It adds targeted native features without importing an account registry or policy model.

EIP-8130 is **configuration-first**: its Keystore, actors, authenticators, scopes, policies, lifecycle operations, and configuration channels make account authority protocol-readable. Canonical validation becomes more predictable, but the protocol owns a much larger account surface.

## Feature matrix

| Dimension | Current EIP-8141 | Upgraded EIP-8141 | EIP-8130 |
|---|---|---|---|
| Transaction | Ordered frames | Frames plus replay, guarantee, binding | Account changes plus call phases |
| Validation | Arbitrary `VERIFY` code | Same, with guarantee exception | Declared authenticator |
| Parallel replay | No | 1–16 keys consumed atomically | One selected key |
| Nonceless | No | Expiry plus consensus replay ring | Validity window plus replay ring |
| Replay consumption | Payment approval | Payment approval, never guarantee | Before account changes/calls |
| Failed sender validation | Invalid | Guarantor pays; sender frames skipped | Rejected before inclusion |
| Sponsorship | Frame-approved payer | Same plus guarantor escrow | Explicit `payer_auth` |
| Batching | Atomic frame groups | Same | Sequential atomic phases |
| Gas | Per-frame execution/state | Same plus replay state gas | One execution pool plus intrinsic costs |
| Native key scopes/expiry | No | No | Yes |
| Account lifecycle | Wallet code | Wallet code | Keystore create/import/lock/delegation |
| `ECRECOVER` bridge | No | Transaction-scoped binding | No equivalent override |

## Three areas where EIP-8130 is stronger

1. **Predictable authentication.** Transactions declare an authenticator. Canonical authenticators have enshrined behavior and fixed validation cost, reducing arbitrary wallet-code simulation and mempool invalidation.
2. **Account lifecycle and portability.** The Keystore standardizes account creation, import, actor changes, locking, delegation, local epochs, and multichain configuration.
3. **Least-privilege actors.** Protocol scopes distinguish initiation, sequenced nonce use, self-payment, sponsorship, and administration. Actors also support expiry and policy-manager gates.

## Three areas where upgraded EIP-8141 is stronger

1. **Atomic multi-key replay.** One transaction can consume up to sixteen ordered nonce domains. EIP-8130 selects exactly one channel.
2. **Guarantor-backed validation.** Validation unsafe for public-mempool simulation may fail during block execution while the guarantor still pays. EIP-8130 requires sender authentication before inclusion.
3. **Existing-application compatibility.** Signer-binding frames let non-secp256k1 account validation authorize digests consumed by existing `ECRECOVER`-based permits and orders.

## Keyed and nonceless replay

The upgraded envelope is:

```text
[chain_id, nonce_keys, nonce_seq, sender,
 frames, signatures, fees, blob_versioned_hashes]
```

- `[0]` uses the sender’s legacy account nonce.
- Non-zero keys below `NONCE_KEY_MAX` use protocol-managed state.
- Multiple keys share one sequence and advance atomically.
- `[NONCE_KEY_MAX]` selects nonceless mode with sequence zero.

These mechanics are normative EIP-8141 behavior, not a dependency on another parallel-nonce EIP. First use of a non-zero key creates 64 durable bytes and costs `97,920` state gas.

Both upgraded EIP-8141 and EIP-8130 use the same nonceless safety pattern: short expiry, a logical replay ID excluding fees and signature bytes, a live-entry map, and a fixed circular buffer.

The integration differs:

- EIP-8130 records replay before account changes and calls.
- EIP-8141 records it only at sender-authorized payment approval.
- A guarantee never consumes sender replay state.
- EIP-8141 reuses its expiry-verifier frame instead of new envelope windows.
- EIP-8141 reserves up to `391,680` state gas plus `13,000` execution gas for replay insertion.

`NONCELESS_EXPIRY_WINDOW` and `REPLAY_BUFFER_CAPACITY` remain coupled L1 activation parameters:

```text
REPLAY_BUFFER_CAPACITY >= peak nonceless throughput
                          × NONCELESS_EXPIRY_WINDOW
```

## Guarantor and signer-binding behavior

`APPROVE_GUARANTEE` escrows maximum cost without consuming sender replay. The canonical paymaster authenticates the full transaction shape and the required settlement frame. Successful sender validation lets settlement consume replay and retain the guarantor as payer. Failed validation advances the paymaster’s `guarantor_nonce`, skips later `SENDER` frames, and still charges the guarantor.

A signer-binding `VERIFY` frame returns one to eight application digests. The protocol maps each digest to the frame target for this transaction. `ECRECOVER` returns the binding on a hit and keeps existing secp256k1 behavior on a miss. No persistent pubkey registry is introduced.

## Implementation complexity

EIP-8130 has the broadest **total account and product surface**: Keystore storage, actors, scopes, policies, configuration replay, import, lock, delegation, canonical authenticators, and native/EVM equivalence.

Upgraded EIP-8141 has the most intricate **transaction state machine**: frame journals, two gas dimensions, payment-time replay, atomic key sets, consensus replay-ring state, a permitted failed-validation path, payer override/refund, and `ECRECOVER` binding.

| Client area | Current 8141 | Upgraded 8141 | EIP-8130 |
|---|---|---|---|
| Execution control | High | Very high | Medium/high |
| Account lifecycle | Low | Low | Very high |
| Canonical validation | Complex simulation | Same ordinary path | Most predictable |
| Mempool dependencies | High | Very high | Low canonical; higher permissive |
| Resource accounting | Two-dimensional | Two-dimensional plus replay | One-dimensional plus intrinsic schedule |

The upgrade conservatively keeps one public pending transaction per sender. Disjoint nonce keys remove replay ordering but do not isolate sender balance, payer balance, account storage, validation dependencies, or replay-ring capacity.

## Requirements and unresolved gates

Upgraded EIP-8141 additionally requires:

- `NONCE_MANAGER` at `address(0x8250)` with fixed reverting code;
- `NONCELESS_REPLAY_MANAGER` at `address(0x8142)`;
- fixed L1 expiry and capacity values;
- the updated canonical paymaster and settlement ABI;
- transaction-scoped signer state and altered `ECRECOVER` lookup;
- clean replacement of the earlier Draft `0x06` encoding.

Before upstreaming:

1. benchmark replay capacity, saturation, reorgs, pruning, and database amplification;
2. publish executable vectors for every replay, approval, guarantee, and binding branch;
3. build two independent execution-client prototypes;
4. differentially test canonical-paymaster Solidity and client behavior;
5. mutation-test replay-ID inclusion and exclusion rules;
6. prove failed guaranteed validation cannot consume sender replay or execute sender frames;
7. audit signer-binding domain separation across permit and order protocols.

## Recommendation

Keep keyed replay, nonceless mode, guarantors, and signer binding inside EIP-8141. Replay consumption is inseparable from `APPROVE`, payer selection, frame gas, receipts, and guarantor settlement.

Do not import EIP-8130’s Keystore, actor registry, scope vocabulary, account locks, multichain configuration, or profile-dependent authenticator policy. Those would replace EIP-8141’s “account as code” boundary rather than extend it.

## Sources

- [Current EIP-8141](https://github.com/ethereum/EIPs/blob/15bc93fd63181f6d1af31e9a93f33f922d13286b/EIPS/eip-8141.md)
- [EIP-8130](https://github.com/ethereum/EIPs/blob/15bc93fd63181f6d1af31e9a93f33f922d13286b/EIPS/eip-8130.md)
- [`EIPS/eip-8141.md`](../EIPS/eip-8141.md), upgraded Draft
- [`EIPS/eip-8141.diff`](../EIPS/eip-8141.diff), exact upstream delta

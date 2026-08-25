## Summary

This PR extends the current EIP-8141 frame transaction with four related capabilities while preserving its account-as-code architecture:

- native keyed replay domains;
- native nonceless transactions;
- guarantor-backed sender validation;
- transaction-scoped signer binding for existing `ECRECOVER` callers.

The proposal is rebased on the current signature-list, two-dimensional-gas, receipt, expiry-verifier, atomic-batch, blob, and public-mempool design. It does not restore the earlier `signer` envelope field, `AuthManager` registry, frame-specific signature hash, or envelope expiry.

## Motivation

The current scalar sender nonce serializes unrelated operations. It also requires counter coordination for short-lived actions. Meanwhile, arbitrary sender validation remains difficult to relay publicly when it cannot safely run under the restrictive mempool rules, and non-secp256k1 accounts still cannot satisfy applications that directly use `ECRECOVER`.

These changes address those gaps without moving account policy into a protocol Keystore or mandatory signer registry.

## Specification changes

### Native replay modes

The envelope replaces scalar `nonce` with an ordered `nonce_keys` list and shared `nonce_seq`:

- `[0]` aliases the legacy account nonce;
- non-zero keys below `NONCE_KEY_MAX` use protocol-managed `NONCE_MANAGER` state;
- up to sixteen keys may be consumed atomically by sender-authorized payment approval;
- `[NONCE_KEY_MAX]` selects nonceless mode with sequence zero.

Nonceless transactions require the expiry verifier as their first frame and use a fee-, gas-limit-, and raw-signature-invariant logical replay ID. Live replay IDs are held in fixed-capacity consensus state under `NONCELESS_REPLAY_MANAGER` and inserted only when sender-authorized payment is approved.

### Guarantors

`APPROVE_GUARANTEE = 0x4` lets the canonical paymaster escrow maximum cost before sender validation. The public mempool validates the guarantee prefix; sender validation then runs during block execution.

If sender validation approves execution, a structurally authenticated settlement frame consumes the selected EIP-8141 replay protection while retaining the guarantor as payer. If validation fails or returns without approval, later `SENDER` frames are skipped and the paymaster advances its own per-sender `guarantor_nonce`. The guarantor pays in either case.

### Signer binding

`SIGNER_BINDING_FLAG = 0x10` identifies a standalone `VERIFY` frame that returns application digests authorized by its target account. The protocol records up to eight `digest -> account` bindings for the transaction.

`ECRECOVER` checks this table first and otherwise follows its existing secp256k1 behavior unchanged. This lets P256, post-quantum, passkey, or account-defined validation interoperate with existing permit and order contracts without persistent public-key storage.

## Rebase decisions

- Uses the existing signature list, `SIGPARAM`, and `SIGDATACOPY`.
- Empty-`msg` sender, payer, and guarantor signatures independently sign the same canonical transaction hash; no second frame hash is added.
- Uses `limits = [execution, state]` and prices durable replay state through EIP-8037 state gas.
- Keeps the existing expiry-verifier frame instead of adding envelope deadline fields.
- Makes EIP-8141 the normative owner of keyed and nonceless replay semantics. EIP-8250 and EIP-8130 are design provenance only.
- Adds no new opcode number, precompile, account-RLP field, or mandatory pubkey registry.

## Protocol and implementation impact

- Approval scope expands to three bits; `ATOMIC_BATCH_FLAG` moves to `0x08` and signer binding uses `0x10`.
- `FRAMEPARAM(0x0C)` exposes the actual approved scope of a completed frame.
- Two system-state accounts hold keyed nonce and nonceless replay state.
- Receipts use status `2` for frames skipped after failed guaranteed validation.
- Public-mempool rules add a canonical guarantee prefix plus keyed/nonceless replacement identities and state dependencies.
- The canonical paymaster accepts protocol-validated secp256k1 or P256 signature entries and authenticates its settlement frame.

## Draft activation gates

`NONCELESS_EXPIRY_WINDOW` and `REPLAY_BUFFER_CAPACITY` intentionally remain unspecified L1 activation parameters. They must be fixed together from worst-case throughput, saturation, reorg, pruning, and database benchmarks before the EIP advances beyond Draft.

The proposal also needs executable state-transition vectors, independent client prototypes, canonical-paymaster differential tests, and formal replay/guarantor invariants.

## Related work

- [Guarantors PR #11555](https://github.com/ethereum/EIPs/pull/11555)
- [EIP-8250](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8250.md), keyed-nonce design provenance
- [EIP-8130](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8130.md), nonceless replay design provenance

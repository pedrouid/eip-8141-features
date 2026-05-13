# Test Matrix

```
Canonical for:  consensus, mempool, and reference-contract test cases for the consolidated EIP
Referenced by:  eip-8141.md (Errata and integration), CLAUDE.md (research-cycle close-out)
```

_Conformance cases that any client implementation of [`/eip-8141.md`](../../eip-8141.md) and any reference-contract change to [`assets/eip-8141/`](../../assets/eip-8141/) MUST pass before external review._

## Hashing

- **TXPARAM(0x08), `compute_sig_hash`**: every VERIFY frame's `data` is elided; SENDER and DEFAULT frame data is preserved. Result is byte-identical for two txs that differ only in VERIFY data.
- **TXPARAM(0x0B), `compute_frame_sig_hash(tx, i)`**: only the data of the VERIFY frame at index `i` is elided; every other VERIFY frame's data is preserved. Vector for: guarantor frame at index `i = g`, sender VERIFY frame at index `g + 1`, expect frame `g`'s hash to bind frame `g + 1`'s data.
- **Atomic-batch flag at bit 3**: `flags = 0x08` is valid on a SENDER frame; `flags = 0x04` is `APPROVE_GUARANTEE` and is invalid on a SENDER frame.

## Guarantor flow

- **Guarantor-backed sender VERIFY failure**: tx is valid; guarantor pays; sender stream advances exactly once at `(tx.sender, tx.signer)`; later SENDER frames are skipped while `sender_approved == false`.
- **Non-guarantor VERIFY failure**: tx is invalid.
- **Guarantor commitment overridden by later `APPROVE_PAYMENT`**: guarantor reservation released; payer pays; nonce stream advances exactly once.
- **bumpNonce frame structural rules**: `bumpNonce` at `current + 2` from the guarantee, `MODE_DEFAULT`, gas ≥ `MIN_BUMP_NONCE_GAS`, data length 68, selector match.

## Nonce semantics

- **`APPROVE_PAYMENT` does not advance the nonce**: only the post-inclusion `consume_nonce` does.
- **`APPROVE_PAYMENT_AND_EXECUTION`**: nonce consumed exactly once on inclusion.
- **`MAX_NONCE` boundary**: tx with `tx.nonce = MAX_NONCE - 1` is the last valid; advance to `MAX_NONCE` succeeds; subsequent tx with `tx.nonce = MAX_NONCE` is statically invalid.
- **`signer == 0` legacy nonce path**: never reads `AUTH_MANAGER`; advance writes the legacy `state[sender].nonce` slot.
- **Non-zero `signer` with missing registration**: pre-frame `checkNonce` returns false; tx is invalid.
- **Atomic-batch rollback**: nonce consumption is outside frame rollback; even if every SENDER frame in a batch reverts, the stream advances once.

## Signer binding

- **`ECRECOVER` hit**: bound `(digest -> address)` returns the address; `(v, r, s)` are unconstrained on hit.
- **`ECRECOVER` miss**: byte-identical to upstream secp256k1 recovery.
- **Duplicate insert, same `(digest, address)`**: no-op; map cardinality unchanged.
- **Conflict, same `digest`, different `address`**: binding frame reverts.
- **Cap exceeded**: `MAX_BOUND_SIGNERS = 8` map entries; ninth distinct entry reverts the inserting frame.
- **Tx-auth payload (`sub_mode = 0x00`)**: signature MUST verify over `compute_sig_hash(tx)` (or `compute_frame_sig_hash` for guarantor-mode frames); a binding payload signature over an arbitrary application digest MUST NOT approve execution or payment.
- **Binding payload (`sub_mode = 0x01`)**: signature verifies over `application_digest`; the frame MUST NOT call `APPROVE` for execution, payment, or guarantee scopes.
- **Pubkey rotation between mempool admission and inclusion**: bindings are rebuilt at execution time; the resolved pubkey is whatever `AUTH_MANAGER.getSigner` returns at execution.

## Expiry

- **Ready at `expiry == 0`**: tx is valid regardless of `block.timestamp`.
- **Ready at `block.timestamp == expiry - 1`**: tx is valid.
- **Expired at `block.timestamp == expiry`**: tx is invalid (exclusive bound).
- **Expired at `block.timestamp > expiry`**: tx is invalid.
- **Replacement expiry**: a replacement that itself fails the expiry check is rejected.

## AuthManager invariants

- **`registerSigner(0, ..., ...)`**: reverts with `ReservedSigner`.
- **`registerSigner` overwrite**: existing entry replaced; nonce stream is NOT touched; pending txs at the original sequence still advance against the new pubkey.
- **`clearSigner(signer)`**: signer entry deleted AND nonce stream cleared; pre-frame `checkNonce` then returns false for that stream.
- **`clearSigner(0)`**: reverts with `ReservedSigner`.
- **`advanceNonce` from non-`SYSTEM_ADDRESS`**: reverts with `NotSystem`.
- **`advanceNonce` for unregistered non-zero signer**: reverts with `SignerNotRegistered`.

## Canonical paymaster

- **Withdrawal request exceeding balance**: `requestWithdrawal` reverts with `WithdrawalExceedsBalance`.
- **`payerNonce == type(uint256).max`** in `bumpNonce`: reverts with `InvalidNonce` (no overflow).
- **Replacement while withdrawal pending**: replacement tx using the same paymaster is admitted iff `available_paymaster_balance` still covers the replacement's max cost.
- **Reorg removes pending withdrawal**: `pending_withdrawal_amount` reservation must be re-added on reorg replay.

## Mempool

- **Restrictive-tier admission for canonical guarantor prefix**: `guarantee` (canonical paymaster code) + `only_verify` + `bump_nonce`, optionally preceded by one `deploy`.
- **Block invalidation on stream advance**: a block that increments `(sender, signer)` invalidates pending txs at the pre-increment sequence on that stream.
- **`MAX_ACTIVE_SIGNERS_PER_SENDER = 16`**: 17th non-zero-signer pending tx for the same sender is rejected.

## Machine-checkable vectors

JSON fixtures should accompany each section. At minimum:

- RLP envelope encodings with `signer`, `nonce`, `expiry`.
- `compute_sig_hash` and `compute_frame_sig_hash` vectors with multiple VERIFY frames.
- TXPARAM and FRAMEPARAM return values for representative txs.
- Canonical paymaster guarantor-mode signature over `TXPARAM(0x0B)`.

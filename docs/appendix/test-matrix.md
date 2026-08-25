# Test Matrix

## Upstream preservation

- Current payload includes `signatures`, grouped `fees`, and frame `limits = [execution, state]`.
- Upstream canonical hash vectors remain unchanged when no new flags are used.
- Upstream atomic batches use bit 3 after this proposal's flag shift and reject approval scope on every batch member.
- Upstream expiry, receipt, gas, blob, access, and validation-prefix vectors remain valid.

## Guarantors

- Guarantee succeeds, sender validation succeeds, sender payment consumes nonce, bump is no-op.
- Guarantee succeeds, sender validation fails, selected replay protection unchanged, bump increments `guarantor_nonce`, `SENDER` frames have status `0x2`.
- Sender validation status `1` with approved scope zero advances `guarantor_nonce` and leaves later `SENDER` frames skipped.
- Failed non-sender `VERIFY` remains transaction-invalid after guarantee.
- Guarantee rejects missing, malformed, wrong-target, wrong-sender, or wrong-nonce bump frame.
- Guarantee rejects a settlement frame whose flags are not exactly `APPROVE_PAYMENT`.
- Guarantee rejects bump execution limit below `40,000`.
- Guarantee rejects settlement state gas below `183,600` for `[0]`, below `391,680` for `[NONCE_KEY_MAX]`, or below `97,920 * len(nonce_keys)` for sequenced non-zero keys.
- Replaying a failed-sender guarantee after bump fails paymaster nonce validation.
- Later payer override refunds guarantor, collects from new payer, and consumes the selected replay protection exactly once.
- Default code rejects `APPROVE_GUARANTEE`.
- `FRAMEPARAM(0x0C)` reports actual approved scope.

## Signer binding

- One valid digest binds to explicit frame target.
- Multiple 32-byte return words bind up to eight unique digests.
- Empty or non-32-byte-aligned return data reverts.
- Duplicate same pair is a no-op; same digest/different target reverts.
- Ninth unique digest reverts.
- Binding frame with any approval scope is statically invalid.
- Binding frame failure is not tolerated by a guarantor.
- `ECRECOVER` hit returns bound account with zero `v`, `r`, `s`.
- `ECRECOVER` miss matches existing precompile vectors byte-for-byte.
- Table clears between transactions and reverts with its binding frame.

## Native keyed nonces

- `[0]` path behaves as legacy sender nonce.
- Non-zero key sets follow EIP-8141 ordering, validation, state-gas-priced first use, and atomic advancement.
- Empty, oversized, unsorted, duplicate, mixed-zero, and exhausted key sets are invalid.
- First use charges `97,920` state gas per non-zero key; later sequence increments add no state bytes.
- Insufficient state gas leaves every selected sequence and every approval effect unchanged.
- `TXPARAM(0x0D)` retains the pre-frame legacy nonce while `TXPARAM(0x0F)` commits to the full selected key set.
- Failed guarantor-backed sender validation does not consume any selected key.
- Successful guarantor settlement consumes the selected set once and retains the existing guarantor escrow.

## Native nonceless mode

- `[NONCE_KEY_MAX]` requires sequence zero and a bounded expiry verifier.
- Nonceless intrinsic execution gas includes the fixed `13,000` replay-bookkeeping charge.
- Replay identifier is unchanged by fee bumps, frame gas-limit changes, and raw-signature changes.
- Replay identifier changes with sender, frames, values, expiry, signer metadata, or signed messages.
- Duplicate live `(sender, replay_id)` is invalid.
- Full live buffer rejects; elapsed head entries evict deterministically.
- Same-block duplicate inclusion is invalid.
- Reorg restores replay ring, live map, and head exactly.
- Payment approval with less than the actual insertion state-gas charge leaves replay state and approval unchanged.
- Successful guarantor settlement reserves `391,680` state gas and inserts once; failed sender validation inserts nothing and advances `guarantor_nonce`.

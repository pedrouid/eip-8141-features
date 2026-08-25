# Guarantors

## Purpose

A guarantor is a canonical paymaster that commits to paying for a frame transaction even if sender validation fails. Public mempool nodes validate only the guarantee prefix and do not simulate the sender's arbitrary validation logic.

## Execution invariant

`APPROVE(APPROVE_GUARANTEE)`:

- collects the maximum cost from the guarantor;
- sets `payer` and `guarantor`;
- does not approve sender execution;
- does not consume the sender's selected sequenced or nonceless replay protection.

Exactly one later `VERIFY` frame with `APPROVE_EXECUTION` scope may fail without invalidating the transaction. If it fails, later `SENDER` frames are skipped. Other `VERIFY` failures remain invalid.

## Replay fallback

Not consuming the sender's selected replay protection prevents a guarantor from advancing account replay state without account authorization. The canonical paymaster instead requires:

```text
guarantee VERIFY
sender-validation VERIFY
bumpNonce DEFAULT
```

The guarantee's canonical signature covers the exact frame list. The paymaster checks the settlement frame target, mode, exact `APPROVE_PAYMENT` flags, selector, sender, expected `guarantor_nonce`, and both gas dimensions before approving.

The settlement frame requires at least:

- `40,000` execution gas;
- `183,600` state gas for the legacy `[0]` path; or
- `97,920 * len(nonce_keys)` state gas for a non-zero key set.

If sender validation failed or returned without approving execution, the frame increments `guarantor_nonce[sender]`. Only status `1` with actual approved scope `APPROVE_EXECUTION` calls `APPROVE_PAYMENT`, consumes the selected sequenced nonce set or inserts the nonceless replay ID, and keeps the guarantor as payer.

## Payer override

After sender approval, a later `APPROVE_PAYMENT` or combined approval may replace the guarantor. The protocol refunds the guarantor's maximum-cost escrow, collects it from the new payer, clears guarantor context, and consumes the selected replay protection.

## Keyed nonce composition

Successful sender-authorized payment consumes the native EIP-8141 nonce-key set. Failed sender validation consumes no sender key. Guarantor replay remains isolated in the paymaster.

## Mempool

The guarantee frame must target exact canonical-paymaster runtime code. Nodes reserve maximum cost against the paymaster balance and pending withdrawal. Sender validation and the bump frame are structurally authenticated by the paymaster but are outside prefix simulation.

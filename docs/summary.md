## Summary

This PR extends the current EIP-8141 frame transaction with four related capabilities while preserving its account-as-code architecture:

- native keyed replay domains;
- native nonceless transactions;
- guarantor-backed sender validation;
- transaction-scoped signer binding for existing `ECRECOVER` callers.

## Motivation

EIP-8141 currently has four gaps:

- Every transaction uses the sender's single nonce, so unrelated actions cannot progress independently.
- Short-lived transactions still require wallets and relayers to coordinate a counter.
- The public mempool cannot safely relay accounts whose validation falls outside its restricted simulation rules unless another party accepts the cost of failed validation.
- Existing permit, order, and meta-transaction contracts often call `ECRECOVER` directly, preventing accounts that use P256, passkeys, post-quantum signatures, or other authentication schemes from using them.

Keyed replay domains separate unrelated transaction flows. Nonceless mode removes counter coordination for short-lived transactions. Guarantors make arbitrary sender validation relayable by paying even when validation fails. Signer binding lets account-defined authentication work with existing `ECRECOVER` contracts. Account authorization remains in account code.

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

`ECRECOVER` checks this table first and otherwise follows its existing secp256k1 behavior unchanged. Inspired by EIP-8164's native alternative-key authentication, this lets P256, post-quantum, passkey, or account-defined validation interoperate with existing permit and order contracts. Unlike EIP-8164's native-key designator, the binding and key material are not persisted by this mechanism.

## Related work

- [Guarantors PR #11555](https://github.com/ethereum/EIPs/pull/11555)
- [EIP-8250](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8250.md), keyed-nonce design provenance
- [EIP-8130](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8130.md), nonceless replay design provenance
- [EIP-8164](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8164.md), alternative-key authentication and signer-binding motivation

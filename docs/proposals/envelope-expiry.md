# Envelope Expiry

_Historical comparison only. Superseded by the current EIP-8141 expiry verifier frame._

## Original goal

Add a one-sided `uint64 expiry` to the transaction envelope so consensus rejects stale transactions and public mempools can drop them deterministically.

## Why it was dropped

Current EIP-8141 already defines `EXPIRY_VERIFIER = address(0x8141)`. A canonical `VERIFY` frame carries exactly eight bytes of deadline data. The full frame is covered by the canonical signature hash, the runtime checks `block.timestamp <= expiry`, and public nodes drop expired transactions.

That mechanism provides the original outcome without charging an envelope field to every transaction. Keeping both paths would duplicate:

- deadline encoding;
- consensus checks;
- mempool eviction;
- wallet construction and RPC errors;
- security analysis.

The consolidated draft therefore adds no envelope expiry, `TXPARAM` field, or deadline-specific replacement rule.

## Comparison

| Property | Envelope field | Expiry verifier |
|---|---|---|
| Optional per transaction | Encoded zero when unused | Omit frame |
| Canonical hash coverage | Direct field | Ordinary frame data |
| Consensus enforcement | Pre-frame check | Canonical verifier runtime/direct evaluation |
| Public expiry eviction | Yes | Yes |
| Extra envelope width | Yes | No |
| Reuses upstream | No | Yes |

## Interaction with nonceless mode

Native nonceless mode requires an expiry verifier and adds a maximum permitted window. It does not revive envelope expiry. The replay identifier includes the verifier frame, so changing the deadline creates a different logical transaction.

## Remaining distinct idea

One-sided expiry does not provide scheduled activation. The sibling [`validity-windows.md`](validity-windows.md) retains `valid_after` as a separate comparison, but scheduled transactions can normally remain offchain until eligible and are not part of the consolidated bundle.

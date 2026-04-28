# Signer Binding for EIP-8141

```
Status:             research draft
Phase:              1
Alternative ID:     P1.S
Depends on:         EIP-8141 + guarantors
Introduces:         PubkeyRegistry, verified-signers table, modified ECRECOVER
Shared appendices:  system-contracts, verified-signers, mempool-tiers, sighash-binding, pq-analysis
```

## 1. Status and scope

Phase-1 alternative (individual). Adds a tx-scoped mechanism that lets PQ accounts be recognized by immutable contracts that call `ECRECOVER` on application digests. The secp256k1 path is byte-for-byte unchanged. Constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md).

## 2. Motivation

EIP-8141's tx-level authentication is PQ-flexible via the VERIFY-frame `signature_type` byte. But immutable contracts that call `ECRECOVER` on an application digest (ERC-2612 `permit`, WETH, raw `ecrecover`) derive the signer from a secp256k1 signature and cannot be redeployed. PQ accounts are locked out of every existing such contract. Signer binding lets a PQ VERIFY frame bind `(digest, account)` claims that `ECRECOVER` resolves on subsequent calls within the same tx, so legacy contracts continue to work without redesign.

## 3. Priorities and non-goals

Priorities:

1. `ECRECOVER` keeps its `(digest, v, r, s)` shape and miss-path semantics.
2. Binding is additive; secp256k1 accounts unaffected.
3. Single pubkey source: `PubkeyRegistry`. Inline envelope pubkeys are explicitly rejected.
4. Tx-scoped table only. No persistent state pollution.

Non-goals:

- Block-builder aggregation (defer to PQ stage 2).
- Cross-tx binding (would expand replay surface).
- Non-32-byte digests.
- Inline envelope pubkeys.
- Pubkey rotation outside `PubkeyRegistry.register` + `clear`.

## 4. Single-line spec delta

Deploy immutable `PubkeyRegistry` at a reserved address. A successful PQ VERIFY frame writes `(digest, frame.target)` into a tx-scoped verified-signers table after resolving the account's pubkey from the registry. `ECRECOVER` consults the table first; hit returns the bound address, miss falls through to existing secp256k1 recovery.

## 5. Normative spec

### Why registry-only (no envelope inlining)

Every NIST PQC scheme has at least one element (pk or sig) measured in kilobytes; carrying both per-tx multiplies mempool bandwidth and witness size. Registry-only bounds per-tx cost to one storage slot read regardless of scheme. Size analysis in [`appendix/pq-analysis.md`](../appendix/pq-analysis.md).

### Registry

`PubkeyRegistry` (interface, deployment, immutability rationale, code-hash pinning, first-use cost) is specified in [`appendix/system-contracts.md`](../appendix/system-contracts.md). Per-account `(scheme_id, pubkey_bytes)` keyed by address; `register` is `msg.sender == account` only.

### Verified-signers table and modified ECRECOVER

Lifecycle, population rule, conflict semantics, and modified `ECRECOVER` pseudocode are specified in [`appendix/verified-signers.md`](../appendix/verified-signers.md). Summary:

- Table is tx-scoped: cleared at tx entry, populated during VERIFY, queried during SENDER.
- A binding VERIFY frame MUST satisfy: `signature_type != 0x0`; carries 32-byte digest + PQ signature; signature verifies under `PubkeyRegistry.get(frame.target)`; calls `APPROVE`.
- Conflicts (same digest, different address) MUST revert the frame.
- `ECRECOVER` MUST consult the table first; on miss, MUST fall through to existing secp256k1 recovery byte-identically.
- Per-tx cap: `MAX_BOUND_SIGNERS = 8` (MUST NOT exceed).

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **Cap enforcement:** `MAX_BOUND_SIGNERS = 8` per tx (also §5). Exceeding causes the binding frame to revert.
- **Conflict revert:** a `(digest, address)` conflict in a binding frame reverts the frame (also §5).

### Node policy (SHOULD)

- **Restrictive-tier admission:** pubkey resolution is one storage slot read on `PubkeyRegistry`. PQ verification gas is absorbed by the 100 000 validation-prefix budget once stage-2 PQ precompiles ship; before then, binding txs route through the expansive tier.
- **Sighash:** in-frame digest claims sit inside VERIFY data, elided as today. RBF and block-invalidation are unchanged; the verified-signers table is rebuilt per-tx.

## 7. RPC and wallet surface

```
eth_getRegisteredPubkey(address, blockTag) → (uint16, bytes) | null
eth_simulateSignerBinding(tx)              → list[(digest, address)]
```

Error codes: `pubkey_not_registered`, `pubkey_scheme_mismatch`, `pubkey_address_mismatch`, `signer_binding_cap_exceeded`.

Wallet UX: surface "this tx will let `<contract>` recognize you as `<address>` via `permit`" before signing. Hardware wallets parse the registry registration tx natively as a one-time onboarding step. Permit composition: the wallet adds a binding VERIFY frame whose `digest` matches the EIP-712 hash the contract recomputes; the SENDER frame calls `permit(...)` normally; the contract's internal `ecrecover` resolves via the bound entry.

## 8. Security and DoS analysis

- **Binding integrity.** A binding claim's integrity comes from the PQ-signature-over-pubkey check at VERIFY time, not from tx-sighash binding (Class B in [`appendix/sighash-binding.md`](../appendix/sighash-binding.md)). The pubkey is fetched from the registry under `frame.target`, so a binding cannot be forged without a valid signature under that account's registered pubkey.
- **Conflict handling.** Write-once entries prevent later frames from silently overriding earlier bindings. Conflicts revert; partial binding state cannot leak.
- **Cap.** `MAX_BOUND_SIGNERS = 8` bounds table-population cost; matches approve + swap + repay redemption shapes.
- **Mempool DoS.** Without stage-2 PQ precompiles, PQ verify is a CPU cost in restrictive tier. Routing PQ-binding txs to the expansive tier in the interim avoids public-mempool DoS.
- **Registry growth.** Bounded by one entry per registered account; PQ migration is infrequent and pubkey calldata dominates first-registration cost.
- **EIP-8151 composition.** A revoked-secp256k1 account with a registered PQ pubkey resolves only via signer binding; un-bound digests return zero. No silent recovery to a revoked key.

## 9. Compatibility and interactions

- **2D nonces:** orthogonal. Binding scope is tx-local; nonce-stream selection is tx-level.
- **Validity windows:** orthogonal. The verified-signers table is rebuilt per-tx; window enforcement runs before any frame.
- **Guarantors:** orthogonal. A guarantor-backed tx may include binding PQ VERIFY frames; the guarantor's commitment is independent.
- **EIP-8151:** complementary. EIP-8151 zeros revoked-key recovery; signer binding provides the positive PQ path for the same address.
- **EIP-8164:** complementary. EIP-8164 reserves an address space rooted in a PQ pubkey hash; signer binding lets that address be recognized by immutable `ECRECOVER` callers.
- **vs. EIP-8151 alone:** EIP-8151 zeros `ecrecover` for revoked keys, bricking `permit` for migrated accounts. Signer binding restores the positive path.
- **vs. redeploying every contract:** no realistic path for WETH, ERC-2612 ERC-20s, Uniswap V2 pairs.
- **vs. a new `PQVERIFY` precompile:** helps only contracts written after it lands; signer binding helps contracts already deployed.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q12 | PQ size caps for follow-on uses (e.g., Phase-2 permissions) | Best-guess; see [`docs/overview.md`](../overview.md) open uncertainties. Phase-2 only. |

No open questions block this proposal.

## 11. Appendix references

- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for `PubkeyRegistry`.
- [`appendix/verified-signers.md`](../appendix/verified-signers.md) for table lifecycle and modified `ECRECOVER`.
- [`appendix/pq-analysis.md`](../appendix/pq-analysis.md) for scheme sizes and the registry-only argument.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class B reasoning.

## 12. Spec delta summary

1. Deploy immutable `PubkeyRegistry` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
2. Tx-scoped verified-signers table per [`appendix/verified-signers.md`](../appendix/verified-signers.md).
3. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
4. Mempool: `MAX_BOUND_SIGNERS = 8`; restrictive tier admits registry-source binding.
5. RPC: `eth_getRegisteredPubkey`, `eth_simulateSignerBinding`, four error codes.

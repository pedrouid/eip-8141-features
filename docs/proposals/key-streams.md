# Key Streams for EIP-8141

```
Status:             research draft
Depends on:         EIP-8141 + guarantors
Introduces:         signer envelope field, AuthManager (merged), verified-signers table, modified ECRECOVER
Shared appendices:  system-contracts, verified-signers, mempool-tiers,
                    sighash-binding, guarantors, pq-analysis
```

## 1. Status and scope

Aggregated alternative. Lands Flexible nonces and signer binding in one upgrade. This doc is the merged spec; sections labelled **Inherited from §X** restate component content for completeness, sections labelled **New** cover the cross-feature analysis. Constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md). Identified as the middle ground in [`docs/priorities.md`](../priorities.md).

## 2. Motivation

Each component is independently small but shares the same precedent (EIP-4788 / EIP-2935 system contracts), the same restrictive-tier reasoning, and the same review burden. Bundling them avoids reopening that precedent twice across two upgrades. The components are pairwise orthogonal at the consensus rule level: per-stream nonce sequencing has nothing to do with per-account PQ signer binding, but the state they require collapses cleanly into a single canonical authentication-state contract (`AuthManager`) instead of two parallel registries.

## 3. Priorities and non-goals

Priorities:

1. One envelope field: `signer`. No envelope field for signer binding.
2. One system contract: `AuthManager`, holding both keyed nonce streams and registered signers. Immutable.
3. `ECRECOVER` ABI unchanged; binding is hit-path-first with byte-identical miss-path.
4. Universal EOA coverage on activation day for nonce streams; opt-in PQ signer binding via registration.

Non-goals:

- Pruning / reclamation of nonce-stream slots (v2).
- Block-builder binding aggregation (defer to PQ stage 2).
- Cross-tx binding. Inline envelope pubkeys.
- Recurring scheduling, on-chain schedulers (handled by the time-bound alternatives Envelope expiry / Validity windows if adopted).

## 4. Single-line spec delta

Add envelope field `signer: uint64` (default 0). Deploy immutable `AuthManager` at a reserved address, holding per-account `(signer, schemeId, pubkey)` entries and per-account per-signer 64-bit nonce sequences. Consensus pre-tx system-calls `AuthManager` for non-zero `signer`. PQ VERIFY frames bind `(digest, address)` entries in a tx-scoped verified-signers table using pubkeys resolved from `AuthManager`; `ECRECOVER` consults the table first, falls through to existing secp256k1 recovery on miss.

## 5. Normative spec

### Envelope

```
[chain_id, signer, nonce, sender, frames, fees..., blob_versioned_hashes]
```

- `signer: uint64`, signer selector. Default 0 (legacy ECDSA / account-nonce path). Differs from the standalone Flexible-nonces alternative which uses `nonce_key: uint256` because the merged `AuthManager` indexes both nonce streams and signer entries by the same per-account `signer` identifier; PQ pubkeys are too large to index protocol state directly.
- `nonce: uint64`, sequence within the per-signer stream (legacy account nonce when `signer == 0`).

Both envelope-native; `compute_sig_hash` covers them. No envelope field for signer binding. MUST NOT add a sighash rule change.

### System contract (Inherited; spec in appendix)

`AuthManager` is specified in [`appendix/system-contracts.md`](../appendix/system-contracts.md). Single reserved address, address + code hash pinned, immutable. Holds keyed nonce streams and signer registrations under one storage layout. First-use cost is SSTORE-from-zero on first nonce-stream touch and on first signer registration.

### Pre-tx consensus check (MUST)

```
// Pre-frame (consensus equality check only; no advance)
if tx.signer == 0:
    require tx.nonce == state[tx.sender].nonce
else:
    require AUTH_MANAGER.checkNonce(tx.sender, tx.signer, tx.nonce)

// (Post-inclusion advance runs once after the validity rule resolves; see consolidated EIP)

clear tx.verified_signers
```

Signer binding runs during VERIFY-frame execution, not pre-tx.

### Stream invariants (Inherited from `flexible-nonces.md` §5; MUST)

Stream-advance-on-inclusion (cited from [`appendix/guarantors.md`](../appendix/guarantors.md)); overflow at `2^64 - 1` is unreachable (last valid sequence is `2^64 - 2`); contract-creation address derivation uses legacy `nonce` only; sponsor signatures bind `(sender, signer, tx.nonce)`.

### Binding semantics (Inherited from `signer-binding.md` §5; spec in appendix)

Verified-signers table lifecycle, population rule (four conditions), conflict semantics, and modified `ECRECOVER` pseudocode are specified once in [`appendix/verified-signers.md`](../appendix/verified-signers.md). Per-tx cap: `MAX_BOUND_SIGNERS = 8` (MUST NOT exceed).

### Account-code visibility (Inherited)

`tx.signer` SHALL be exposed on the default-code tx-context surface.

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **Block-invalidation (stream side):** stream increment invalidates pending txs at pre-increment sequence on that stream.
- **Cap enforcement:** `MAX_BOUND_SIGNERS = 8` per tx (binding side); see [`appendix/verified-signers.md`](../appendix/verified-signers.md).
- **Sponsor binding:** sponsor signatures MUST bind `(sender, signer, tx.nonce)`.

### Node policy (SHOULD)

- **Restrictive-tier admission, nonce side:** one storage slot read against `AuthManager` (`getNonce`).
- **Restrictive-tier admission, binding side:** one storage slot read against `AuthManager` (`getSigner`) per binding frame; PQ verification gas absorbed by the 100 000 validation-prefix budget once stage-2 PQ precompiles ship; before then, binding txs route through expansive tier.
- **Readiness:** `tx.nonce == AUTH_MANAGER.getNonce(sender, signer)` (or legacy when `signer == 0`). Streams independent.
- **RBF:** matches `(sender, signer, tx.nonce)`.
- **DoS caps:** `MAX_ACTIVE_SIGNERS_PER_SENDER = 16` (mempool only; stream consensus is unbounded). Consensus-side cap on bindings is the `MAX_BOUND_SIGNERS = 8` above.

## 7. RPC and wallet surface

```
eth_getTransactionCountBySigner(address, signer, blockTag) → uint64
eth_getRegisteredPubkey(address, blockTag)                 → (uint16, bytes) | null
eth_simulateSignerBinding(tx)                              → list[(digest, address)]
```

Error codes:

- Nonce side: `signer_not_registered`, `too_many_active_signers`.
- Binding side: `pubkey_not_registered`, `pubkey_scheme_mismatch`, `pubkey_address_mismatch`, `signer_binding_cap_exceeded`.

Wallet UX:

- **Streams:** signer 0 shown as "Main sequence #n"; known signers labeled by wallet convention (e.g., "Hot key", "Session key"); first use of a non-zero signer warned for the SSTORE-from-zero surcharge.
- **Signer binding:** one-time onboarding flow registers the account's PQ pubkey via a SENDER frame calling `AuthManager.registerSigner(signer, scheme, pubkey)`; the wallet picks the `signer` id (any non-zero `uint64`) and uses it as the envelope `signer` field on subsequent txs. Each tx surfaces "this tx will let `<contract>` recognize you as `<address>` via `permit`" before signing.

## 8. Security and DoS analysis

Per-feature analyses in [`flexible-nonces.md`](flexible-nonces.md) §8 and [`signer-binding.md`](signer-binding.md) §8 carry over. **New** cross-feature considerations:

- **Cross-feature DoS budget.** A single tx can both touch a non-zero stream (1 SSTORE on `AuthManager` for first-use, otherwise 1 slot read) and emit up to 8 signer bindings (1 slot read on `AuthManager` each). Restrictive-tier admission still admits both flows; the 100 000 validation-prefix budget covers them.
- **First-use cost stacking.** A new account's first usage may pay first-use SSTORE on both the nonce side and the signer side of `AuthManager`. Wallet UX should warn once per side on first onboarding.
- **Independence under failure.** Either component can be pulled late without invalidating the other; the two halves of `AuthManager` (nonce streams and signer entries) do not cross-reference at the storage layer.

## 9. Compatibility and interactions

- **Envelope expiry / Validity windows** (if also adopted, as in Auth scopes): orthogonal. A time-bound tx holds its stream position until it lands or expires; the verified-signers table is rebuilt per-tx.
- **Guarantors:** confirms stream-advance invariant; orthogonal to signer binding.
- **Sighash binding:** Flexible-nonce key bound by envelope placement (Class A); binding digests sit in elided VERIFY data, integrity covered by signature-over-pubkey check (Class B). See [`appendix/sighash-binding.md`](../appendix/sighash-binding.md).
- **vs. shipping each individually across upgrades:** same protocol surface, one upgrade's review effort, shared system-contract precedent, shared mempool reasoning.
- **vs. ERC-4337:** 4337 packs key+seq into one `uint256` because it lives above the protocol; key-streams uses two envelope fields. ERC-4337 has no analogue to signer binding.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `AuthManager` nonce-side storage | Best-guess; see [`docs/overview.md`](../overview.md) open uncertainties. |

## 11. Appendix references

- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for `AuthManager`.
- [`appendix/verified-signers.md`](../appendix/verified-signers.md) for binding mechanism.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A and Class B binding.
- [`appendix/guarantors.md`](../appendix/guarantors.md) for stream-advance invariant.
- [`appendix/pq-analysis.md`](../appendix/pq-analysis.md) for scheme sizes and registry-only argument.

## 12. EIP-ready delta

1. Envelope: add `signer: uint64` before `nonce`.
2. Reinterpret `tx.nonce: uint64` as per-stream sequence.
3. Deploy immutable `AuthManager` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
4. Pre-tx rule: non-zero keys system-call `AuthManager.checkNonce` + `advanceNonce`; tx-scoped verified-signers table cleared.
5. PQ VERIFY frames bind `(digest, target)` per [`appendix/verified-signers.md`](../appendix/verified-signers.md).
6. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
7. RPC: `eth_getTransactionCountBySigner`, `eth_getRegisteredPubkey`, `eth_simulateSignerBinding`; error codes as listed.
8. Mempool: per-signer RBF, `MAX_ACTIVE_SIGNERS_PER_SENDER = 16`, `MAX_BOUND_SIGNERS = 8`, block-invalidation rule.
9. Stream advance on inclusion regardless of VERIFY outcome (normative).

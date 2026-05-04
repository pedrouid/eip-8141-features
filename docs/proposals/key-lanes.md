# Key Lanes for EIP-8141

```
Status:             research draft
Alternative ID:     NS
Depends on:         EIP-8141 + guarantors
Introduces:         nonce_key envelope field, NonceLaneRegistry, PubkeyRegistry,
                    verified-signers table, modified ECRECOVER
Shared appendices:  system-contracts, verified-signers, mempool-tiers,
                    sighash-binding, guarantors, pq-analysis
```

## 1. Status and scope

Aggregated alternative. Lands flexible nonces (N) and signer binding (S) in one upgrade. This doc is the merged spec; sections labelled **Inherited from §X** restate component content for completeness, sections labelled **New** cover the cross-feature analysis. Constraints respected (no new opcodes, precompiles, frame modes, account-encoding changes, sighash changes) are listed in [`docs/overview.md`](../overview.md). Identified as the middle ground in [`docs/priorities.md`](../priorities.md).

## 2. Motivation

Each component is independently small but shares the same precedent (EIP-4788 / EIP-2935 system contracts), the same restrictive-tier reasoning, and the same review burden. Bundling them avoids reopening that precedent twice across two upgrades. The components are pairwise orthogonal at the consensus rule level: per-stream nonce sequencing has nothing to do with per-account PQ signer binding.

## 3. Priorities and non-goals

Priorities:

1. One envelope field: `nonce_key`. No envelope field for signer binding.
2. Two system contracts: `NonceLaneRegistry` and `PubkeyRegistry`. Both immutable.
3. `ECRECOVER` ABI unchanged; binding is hit-path-first with byte-identical miss-path.
4. Universal EOA coverage on activation day for nonce streams; opt-in PQ signer binding via registration.

Non-goals:

- Pruning / reclamation of nonce-lane slots (v2).
- Block-builder binding aggregation (defer to PQ stage 2).
- Cross-tx binding. Inline envelope pubkeys.
- Recurring scheduling, on-chain schedulers (separate alternative if validity windows are adopted).

## 4. Single-line spec delta

Add envelope field `nonce_key: uint256` (default 0). Deploy two immutable system contracts at reserved addresses: `NonceLaneRegistry` (per-account per-key 64-bit sequence) and `PubkeyRegistry` (per-account `(scheme, pubkey)`). Consensus pre-tx system-calls `NonceLaneRegistry` for non-zero keys. PQ VERIFY frames bind `(digest, address)` entries in a tx-scoped verified-signers table from registry pubkeys; `ECRECOVER` consults the table first, falls through to existing secp256k1 recovery on miss.

## 5. Normative spec

### Envelope (Inherited from §5 of `flexible-nonces.md`)

```
[chain_id, nonce_key, nonce, sender, frames, fees..., blob_versioned_hashes]
```

- `nonce_key: uint256`, stream selector. Default 0.
- `nonce: uint64`, sequence within the stream.

Both envelope-native; `compute_sig_hash` covers them. No envelope field for signer binding. MUST NOT add a sighash rule change.

### System contracts (Inherited; specs in appendix)

`NonceLaneRegistry` and `PubkeyRegistry` are specified once in [`appendix/system-contracts.md`](../appendix/system-contracts.md). Both at upgrade-coordinated reserved addresses, address + code hash pinned, immutable. First-use cost is SSTORE-from-zero in each.

### Pre-tx consensus check (MUST)

```
if tx.nonce_key == 0:
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require NONCE_REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    NONCE_REGISTRY.advance(tx.sender, tx.nonce_key)

clear tx.verified_signers
```

Signer binding runs during VERIFY-frame execution, not pre-tx.

### Stream invariants (Inherited from `flexible-nonces.md` §5; MUST)

Stream-advance-on-inclusion (cited from [`appendix/guarantors.md`](../appendix/guarantors.md)); `2^64 - 1` overflow rule; contract-creation address derivation uses legacy `nonce` only; sponsor signatures bind `(sender, nonce_key, tx.nonce)`.

### Binding semantics (Inherited from `signer-binding.md` §5; spec in appendix)

Verified-signers table lifecycle, population rule (four conditions), conflict semantics, and modified `ECRECOVER` pseudocode are specified once in [`appendix/verified-signers.md`](../appendix/verified-signers.md). Per-tx cap: `MAX_BOUND_SIGNERS = 8` (MUST NOT exceed).

### Account-code visibility (Inherited)

`tx.nonce_key` SHALL be exposed on the default-code tx-context surface.

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **Block-invalidation (lane side):** lane increment invalidates pending txs at pre-increment sequence on that lane.
- **Cap enforcement:** `MAX_BOUND_SIGNERS = 8` per tx (binding side); see [`appendix/verified-signers.md`](../appendix/verified-signers.md).
- **Sponsor binding:** sponsor signatures MUST bind `(sender, nonce_key, tx.nonce)`.

### Node policy (SHOULD)

- **Restrictive-tier admission, nonce side:** one storage slot read against `NonceLaneRegistry`.
- **Restrictive-tier admission, binding side:** one storage slot read against `PubkeyRegistry` per binding frame; PQ verification gas absorbed by the 100 000 validation-prefix budget once stage-2 PQ precompiles ship; before then, binding txs route through expansive tier.
- **Readiness:** `tx.nonce == NONCE_REGISTRY.get(sender, key)` (or legacy for key 0). Streams independent.
- **RBF:** matches `(sender, nonce_key, tx.nonce)`.
- **DoS caps:** `MAX_ACTIVE_STREAMS_PER_SENDER = 16` (mempool only; lane consensus is unbounded). Consensus-side cap on bindings is the `MAX_BOUND_SIGNERS = 8` above.

## 7. RPC and wallet surface

```
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64
eth_getRegisteredPubkey(address, blockTag)                 → (uint16, bytes) | null
eth_simulateSignerBinding(tx)                              → list[(digest, address)]
```

Error codes:

- Nonce side: `lane_not_found`, `too_many_active_streams`.
- Binding side: `pubkey_not_registered`, `pubkey_scheme_mismatch`, `pubkey_address_mismatch`, `signer_binding_cap_exceeded`.

Wallet UX:

- **Lanes:** key 0 shown as "Main sequence #N"; known lanes labeled by wallet convention; first-use of a non-zero lane warned for the SSTORE-from-zero surcharge.
- **Signer binding:** one-time onboarding flow registers the account's PQ pubkey via a SENDER frame to `PubkeyRegistry`. Subsequent txs surface "this tx will let `<contract>` recognize you as `<address>` via `permit`" before signing.

## 8. Security and DoS analysis

Per-feature analyses in [`flexible-nonces.md`](flexible-nonces.md) §8 and [`signer-binding.md`](signer-binding.md) §8 carry over. **New** cross-feature considerations:

- **Cross-feature DoS budget.** A single tx can both touch a non-zero lane (1 SSTORE on `NonceLaneRegistry` for first-use, otherwise 1 slot read) and emit up to 8 signer bindings (1 slot read on `PubkeyRegistry` each). Restrictive-tier admission still admits both flows; the 100 000 validation-prefix budget covers them.
- **First-use cost stacking.** A new account's first usage may pay first-use SSTORE on both registries. Wallet UX should warn once per registry on first onboarding.
- **Independence under failure.** Either component can be pulled late without invalidating the other; spec language and storage layouts do not cross-reference.

## 9. Compatibility and interactions

- **Validity windows** (if also adopted, e.g., as NSW): orthogonal. Future-valid tx holds its stream position until lands or expires; the verified-signers table is rebuilt per-tx.
- **Guarantors:** confirms stream-advance invariant; orthogonal to signer binding.
- **Sighash binding:** flexible-nonce key bound by envelope placement (Class A); binding digests sit in elided VERIFY data, integrity covered by signature-over-pubkey check (Class B). See [`appendix/sighash-binding.md`](../appendix/sighash-binding.md).
- **vs. shipping each individually across upgrades:** same protocol surface, one upgrade's review effort, shared system-contract precedent, shared mempool reasoning.
- **vs. ERC-4337:** 4337 packs key+seq into one `uint256` because it lives above the protocol; key-lanes uses two envelope fields. ERC-4337 has no analogue to signer binding.

## 10. Open questions

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `NonceLaneRegistry` | Best-guess; see [`docs/overview.md`](../overview.md) open uncertainties. |

## 11. Appendix references

- [`appendix/system-contracts.md`](../appendix/system-contracts.md) for both registries.
- [`appendix/verified-signers.md`](../appendix/verified-signers.md) for binding mechanism.
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.
- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A and Class B binding.
- [`appendix/guarantors.md`](../appendix/guarantors.md) for stream-advance invariant.
- [`appendix/pq-analysis.md`](../appendix/pq-analysis.md) for scheme sizes and registry-only argument.

## 12. Spec delta summary

1. Envelope: add `nonce_key: uint256` before `nonce`.
2. Reinterpret `tx.nonce: uint64` as per-stream sequence.
3. Deploy immutable `NonceLaneRegistry` and `PubkeyRegistry` per [`appendix/system-contracts.md`](../appendix/system-contracts.md).
4. Pre-tx rule: non-zero keys system-call nonce registry; tx-scoped verified-signers table cleared.
5. PQ VERIFY frames bind `(digest, target)` per [`appendix/verified-signers.md`](../appendix/verified-signers.md).
6. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
7. RPC: `eth_getTransactionCountByKey`, `eth_getRegisteredPubkey`, `eth_simulateSignerBinding`; error codes as listed.
8. Mempool: per-lane RBF, `MAX_ACTIVE_STREAMS_PER_SENDER = 16`, `MAX_BOUND_SIGNERS = 8`, block-invalidation rule.
9. Stream advance on inclusion regardless of VERIFY outcome (normative).

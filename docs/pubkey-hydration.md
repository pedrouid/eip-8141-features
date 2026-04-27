# Pubkey Hydration for EIP-8141

_Scratch doc, not indexed on the site._

Closes the gap that keeps EIP-8141 from being post-quantum-ready in practice. Tx-level authentication is PQ-flexible via the VERIFY-frame `signature_type` byte, but immutable contracts that call `ECRECOVER` on an application digest (ERC-2612 `permit`, WETH, raw `ecrecover`) derive the signer from a secp256k1 signature and cannot be redeployed. PQ accounts are locked out of every existing contract.

**Pubkey hydration** is a tx-scoped mechanism where a PQ VERIFY frame registers `(digest, account)` claims that the existing `ECRECOVER` precompile resolves on subsequent calls within the same tx. Pubkeys come from the envelope or a canonical `PubkeyRegistry` system contract (EIP-4788 pattern). The secp256k1 path is byte-for-byte unchanged.

## Priorities

1. No new opcode, no new precompile, no account-encoding change. `ECRECOVER` keeps its `(digest, v, r, s)` shape and miss-path semantics.
2. Hydration is additive; secp256k1 accounts unaffected.
3. Two pubkey sources: `PubkeyRegistry` (long-lived) and envelope (ephemeral, no state read).
4. Tx-scoped table only. No persistent state pollution.
5. Composes with EIP-8151: a revoked-secp256k1 account with a registered PQ pubkey resolves only via hydration; un-hydrated digests return zero.

## 1. Single-line spec delta

> Add envelope field `pubkeys: list[(uint16 scheme, bytes pubkey)]` (default empty). Deploy immutable `PubkeyRegistry` at a reserved address. A successful PQ VERIFY frame writes `(digest, frame.target)` into a tx-scoped verified-signers table. `ECRECOVER` consults the table first; hit returns the bound address, miss falls through to existing secp256k1 recovery.

## 2. Envelope addition

```
[chain_id, nonce_key, nonce, sender, frames, fees...,
 blob_versioned_hashes, valid_after, valid_before, pubkeys]
```

- `pubkeys: list[(uint16, bytes)]` — optional inline pubkey declarations the tx wants the node to consider for the duration of execution. `scheme_id` matches the VERIFY-frame `signature_type` registry. Default empty.

Covered by `compute_sig_hash` via envelope placement; no sighash rule change.

## 3. PubkeyRegistry

```solidity
contract PubkeyRegistry {
    struct Entry { uint16 scheme; bytes pubkey; }
    mapping(address => Entry) private entries;

    function register(uint16 scheme, bytes calldata pubkey) external; // msg.sender == account
    function get(address account) external view returns (uint16, bytes memory);
    function clear() external;                                        // msg.sender == account
}
```

Reserved address, immutable, fork-coordinated; address + code-hash pinning per EIP-4788. Registration is SSTORE-from-zero plus pubkey calldata; clearing is SSTORE-to-zero. Accounts self-register via an EIP-8141 SENDER frame; the protocol does not auto-register.

## 4. Verified-signers table

Cleared at tx entry, populated during validation, queried during execution.

```
table: set[(digest32, address)]
```

A VERIFY frame populates the table iff:

1. `signature_type != 0x0` (secp256k1 needs no hydration).
2. `frame.data` carries a 32-byte application digest (after `signature_type`) followed by the PQ signature.
3. The signature verifies under the declared scheme using a pubkey resolved via §3 (registry-first, envelope-fallback), bound to `frame.target` by the scheme's address rule.
4. The frame calls `APPROVE`.

Multiple claims per frame allowed up to the per-tx cap. Entries are write-once; conflicts revert the frame.

## 5. Modified ECRECOVER

```
ECRECOVER(digest, v, r, s):
    if (digest, addr) in tx.verified_signers:
        return addr                                  // hydration hit
    return existing_secp256k1_recover(digest, v, r, s) // unchanged; EIP-8151 still applies
```

Hit-path cost stays at 3000 gas; the lookup is constant-time, cheaper than an EC operation. `(v, r, s)` are unconstrained on hit; wallets pass zeros. Miss-path is byte-identical to today.

## 6. Mempool rules

- **Restrictive tier**: admits hydrating VERIFY frames whose pubkey source is the registry (one slot read) or the envelope (no state read). The 100 000 validation-prefix gas cap absorbs PQ verification once stage-2 PQ precompiles ship; before then, PQ-hydrating txs route through the expansive tier.
- **Cap per tx**: `MAX_HYDRATED_DIGESTS = 8`. Bounds table-population cost; matches approve + swap + repay.
- **Sighash**: `pubkeys` is signed via envelope placement; in-frame digest claims sit inside VERIFY data, elided as today.
- **RBF / block-invalidation**: unchanged; hydration is rebuilt per-tx.

## 7. RPC

```
eth_getRegisteredPubkey(address, blockTag) → (uint16, bytes) | null
eth_simulateHydration(tx)                  → list[(digest, address)]
```

Error codes: `pubkey_not_registered`, `pubkey_scheme_mismatch`, `pubkey_address_mismatch`, `hydrated_digest_cap_exceeded`.

## 8. Wallet UX

Wallets surface "this tx will let `<contract>` recognize you as `<address>` via `permit`" before signing. Hardware wallets parse `pubkeys` natively. First-use registration is a one-time SSTORE-from-zero cost. Permit composition: the wallet adds a hydrating VERIFY frame whose `digest` matches the EIP-712 hash the contract recomputes; the SENDER frame calls `permit(...)` normally; the contract's internal `ecrecover` resolves via hydration.

## 9. Interactions

- **2D nonces, validity windows, guarantors, execution authority**: orthogonal.
- **Permissions (v2)**: a delegated PQ signer can hydrate on the delegator's behalf when `execution_authority` rebinds `msg.sender`; the claim still requires a valid signature under the delegator's scheme.
- **EIP-8151**: complementary. EIP-8151 zeros revoked-key recovery; hydration provides the positive PQ path for the same address.
- **EIP-8164**: complementary. EIP-8164 reserves an address space rooted in a PQ pubkey hash; hydration lets that address be recognized by immutable `ECRECOVER` callers. Closes the "EIP-8164 + EIP-8141 not composable" gap from PQ roadmap §5.

## 10. Comparison

- **vs. EIP-8151 alone**: EIP-8151 zeros `ecrecover` for revoked keys, bricking `permit` for migrated accounts. Hydration restores the positive path.
- **vs. redeploying every contract**: no realistic path for WETH, ERC-2612 ERC-20s, Uniswap V2 pairs. Hydration is the only protocol-level fix.
- **vs. a new `PQVERIFY` precompile**: helps only contracts written after it lands; hydration helps contracts already deployed.
- **vs. packing PQ signatures into `(v, r, s)`**: shape-incompatible (Falcon ~666 B, Dilithium ~2.4 KB vs 65 B).

## 11. Non-goals

Block-builder aggregation (defer to PQ stage 2). Cross-tx hydration (replay surface). Non-32-byte digests. Rotation outside `register` + `clear`.

## 12. Spec delta summary

1. Add envelope field `pubkeys: list[(uint16, bytes)]`.
2. Deploy immutable `PubkeyRegistry` at a reserved address.
3. Tx-scoped verified-signers table populated by successful PQ VERIFY frames.
4. `ECRECOVER` extended: hit-path returns bound address; miss-path unchanged.
5. Mempool: `MAX_HYDRATED_DIGESTS = 8`; restrictive tier admits registry- and envelope-source hydration.
6. RPC: `eth_getRegisteredPubkey`, `eth_simulateHydration`, four error codes.

**One envelope field. One system contract. One precompile miss-fallthrough. Zero new opcodes, zero new precompiles, zero account-encoding changes.** Immutable contracts calling `ECRECOVER` keep working for secp256k1 accounts (unchanged) and now for PQ accounts (hydrated). The "EIP-8141 doesn't actually fix PQ for existing contracts" gap closes.

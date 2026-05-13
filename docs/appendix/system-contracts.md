# System Contracts: NonceManager, PubkeyRegistry, AuthManager

```
Canonical for:  NonceManager (standalone), PubkeyRegistry (standalone), AuthManager (merged)
Referenced by:  Flexible nonces, Signer binding, Key streams, Auth scopes
```

_Canonical specs for the system contracts the alternatives use. Single source of truth referenced by [`proposals/flexible-nonces.md`](../proposals/flexible-nonces.md), [`proposals/signer-binding.md`](../proposals/signer-binding.md), [`proposals/key-streams.md`](../proposals/key-streams.md), and [`proposals/auth-scopes.md`](../proposals/auth-scopes.md). Related upstream keyed-nonce work lives in [PR #11584](https://github.com/ethereum/EIPs/pull/11584) and draft EIP-8250 [PR #11598](https://github.com/ethereum/EIPs/pull/11598)._

All three contracts follow the EIP-4788 / EIP-2935 system-contract pattern: deployed at upgrade-coordinated reserved addresses, immutable, address + expected code-hash pinned by consensus.

Which contract a proposal deploys depends on which features it ships:

| Proposal | Contract deployed | Address constant |
|---|---|---|
| Validity windows (standalone) | none | n/a |
| Envelope expiry (standalone) | none | n/a |
| Flexible nonces (standalone) | `NonceManager` | `NONCE_MANAGER` |
| Signer binding (standalone) | `PubkeyRegistry` | `PUBKEY_REGISTRY` |
| Key streams (Flexible nonces + signer binding) | `AuthManager` (merged) | `AUTH_MANAGER` |
| Auth scopes (Flexible nonces + signer binding + envelope expiry) | `AuthManager` (merged) | `AUTH_MANAGER` |

The standalone contracts and the merged `AuthManager` are not all deployed at once. An upgrade ships exactly one shape. `AuthManager` is the merge of `NonceManager` + `PubkeyRegistry` and obsoletes both whenever Flexible nonces and Signer binding ship together. Validity windows and Envelope expiry add no contract regardless of which other features ship.

## 1. NonceManager (standalone Flexible nonces)

Holds per-account per-key 64-bit sequence numbers. Used only by the standalone Flexible-nonces proposal.

```solidity
contract NonceManager {
    mapping(address => mapping(uint256 => uint64)) private nonces;

    function check(address sender, uint256 key, uint64 seq) external view returns (bool);
    function advance(address sender, uint256 key) external;  // SYSTEM_ADDRESS only
    function get(address sender, uint256 key) external view returns (uint64);
}
```

Pre-tx system call:

```
// Pre-frame check (equality only)
if tx.nonce_key == 0:
    require tx.nonce == state[tx.sender].nonce
else:
    require REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)

// Post-inclusion advance (single point; outside frame rollback)
if tx.nonce_key == 0:
    state[tx.sender].nonce = tx.nonce + 1
else:
    REGISTRY.advance(tx.sender, tx.nonce_key)
```

First-use cost of a non-zero stream is SSTORE-from-zero (20 000 gas with EIP-2929 refinements). Pruning / reclamation is v2.

## 2. PubkeyRegistry (standalone Signer binding)

Holds per-account `(scheme_id, pubkey_bytes)` for PQ accounts. Used only by the standalone Signer-binding proposal. The verified-signers table that consumes this state is specified in [`appendix/verified-signers.md`](verified-signers.md).

```solidity
contract PubkeyRegistry {
    struct Entry { uint16 scheme; bytes pubkey; }
    mapping(address => Entry) private entries;

    function register(uint16 scheme, bytes calldata pubkey) external; // msg.sender == account
    function get(address account) external view returns (uint16, bytes memory);
    function clear() external;                                        // msg.sender == account
}
```

`scheme_id` matches the VERIFY-frame `signature_type` registry; the registry stays scheme-agnostic at the consensus layer. Curve-specific data lives in [`appendix/pq-analysis.md`](pq-analysis.md).

Registration is SSTORE-from-zero plus pubkey calldata. Clearing is SSTORE-to-zero. Accounts self-register via an EIP-8141 SENDER frame; the protocol does not auto-register.

## 3. AuthManager (merged, used by Key streams and Auth scopes)

`AuthManager` is the merged form of the two standalone registries above. Both signer entries and nonce streams are keyed by `(account, signer)` where `signer: uint64` is chosen by the account at registration. `signer == 0` is reserved for the legacy ECDSA / account-nonce path and never holds a stored entry. The standalone `nonce_key` is replaced by `signer` here because indexing streams or signer entries by raw PQ pubkey is impossible, lattice and multivariate pubkeys are kilobyte-scale; the small uint64 `signer` is the indirection. Used by [`proposals/key-streams.md`](../proposals/key-streams.md), [`proposals/auth-scopes.md`](../proposals/auth-scopes.md), and the consolidated [`/eip-8141.md`](../../EIPS/eip-8141.md) execution.

```solidity
contract AuthManager {
    struct SignerEntry { uint16 schemeId; bytes pubkey; }

    mapping(address => mapping(uint64 => SignerEntry)) private signers;
    mapping(address => mapping(uint64 => uint64))      private nonces;

    function getNonce(address sender, uint64 signer) external view returns (uint64);
    function checkNonce(address sender, uint64 signer, uint64 expectedNonce) external view returns (bool);
    function advanceNonce(address sender, uint64 signer, uint64 expectedNonce) external; // SYSTEM_ADDRESS only

    function registerSigner(uint64 signer, uint16 schemeId, bytes calldata pubkey) external; // msg.sender == account; account chooses the signer id (must be != 0)
    function getSigner(address account, uint64 signer) external view returns (uint16, bytes memory);
    function clearSigner(uint64 signer) external;                                            // msg.sender == account
}
```

Why merge for the aggregated proposals: a single canonical authentication-state contract reduces the upgrade's protocol surface from two reserved addresses, two code-hashes, and two RPC roots to one. Tying the nonce-stream key to the signer means every registered signer automatically has its own stream; raw pubkeys never index protocol state. An account that wants multiple parallel streams registers multiple signers (each with its own `signer` value, possibly the same scheme).

Reference implementation: [`assets/eip-8141/AuthManager.sol`](../../assets/eip-8141/AuthManager.sol).

## 4. Common deployment model

All contracts share:

- **Reserved address**, upgrade-coordinated.
- **Immutable**: address + expected code hash pinned by consensus; default code verifies the code hash before any system call.
- **Upgrades** ship as new reserved addresses at future upgrades. Existing state stays on the old address.
- **Why immutable**: matches the EIP-4788, EIP-2935, and ERC-4337 EntryPoint precedent. Avoids centralising upgrade authority. Migration is explicit and user-visible. Existing state stays valid against the registry it was written against. Prevents rug-pull scenarios.

## 5. Why system contracts and not account-encoding fields

An earlier Flexible-nonces draft proposed adding nonce-stream state to the account RLP encoding (the account 4-tuple: `nonce, balance, storageRoot, codeHash`). Rejected: changing account encoding ripples through every RLP parser, every state-root computation, EIP-161, archive-node decoding, and witness format. The system-contract pattern keeps the change at the storage layer where existing machinery already covers it: snap sync, witnesses, state-tree transitions, archive decoding all work without bespoke code paths.

By extension, signer state uses the same pattern. Storing per-account PQ pubkeys on the account record itself was never seriously considered for the same reasons, with the additional size problem for lattice and multivariate schemes (kilobyte-scale pubkeys would balloon the account RLP).

## 6. VOPS profile

State-growth budget is best-guess pending cross-client benchmarks. Nonce-side: ~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate. Signer-side: bounded by one entry per registered account; PQ migrations are infrequent and pubkey calldata is the dominant cost.

VOPS slicing treats all slots as ordinary storage witnesses. If growth exceeds budget, raise first-use cost via a standard SSTORE-accounting amendment.

## 7. Mempool admission

Restrictive-tier compatible across all three contracts:

- Nonce side: one storage slot read per touched stream (`(sender, nonce_key)` on `NonceManager`, `(sender, signer)` on `AuthManager`).
- Signer side: one storage slot read per binding VERIFY frame.

Restrictive tier definitions live in [`appendix/mempool-tiers.md`](mempool-tiers.md).

## 8. RPC

```
// standalone Flexible nonces
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64
// standalone Signer binding
eth_getRegisteredPubkey(address, blockTag)                 → (uint16, bytes) | null
// Key streams / Auth scopes
eth_getTransactionCountBySigner(address, signer, blockTag) → uint64
eth_getRegisteredPubkey(address, signer, blockTag)         → (uint16, bytes) | null
```

Error codes are listed per-proposal where they apply.

## 9. Spec delta summary

Per alternative:

- Standalone Flexible nonces: deploy `NonceManager`. Pre-tx rule: non-zero `nonce_key` system-calls `check` + `advance`; key 0 retains the legacy account-nonce path.
- Standalone Signer binding: deploy `PubkeyRegistry`. VERIFY frames resolve PQ pubkeys via `get(frame.target)` (semantics in [`appendix/verified-signers.md`](verified-signers.md)).
- Key streams / Auth scopes: deploy `AuthManager` instead of the two standalone contracts. Pre-tx rule: non-zero `signer` system-calls `checkNonce` + `advanceNonce`; signer 0 retains the legacy account-nonce path. VERIFY frames resolve PQ pubkeys via `getSigner(frame.target, signer)`.

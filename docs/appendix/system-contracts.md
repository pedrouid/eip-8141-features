# System Contracts: NonceLaneRegistry and PubkeyRegistry

```
Canonical for:  NonceLaneRegistry, PubkeyRegistry
Referenced by:  N, S, NS, NSW
```

_Canonical specs for the two system contracts introduced by the alternatives. Single source of truth referenced by [`proposals/flexible-nonces.md`](../proposals/flexible-nonces.md), [`proposals/signer-binding.md`](../proposals/signer-binding.md), [`proposals/key-lanes.md`](../proposals/key-lanes.md), and [`proposals/authorization-scopes.md`](../proposals/authorization-scopes.md)._

Both contracts follow the EIP-4788 / EIP-2935 system-contract pattern: deployed at upgrade-coordinated reserved addresses, immutable, address + expected code-hash pinned by consensus.

## 1. NonceLaneRegistry

Holds per-account per-key 64-bit sequence numbers backing flexible nonces. Used by [`proposals/flexible-nonces.md`](../proposals/flexible-nonces.md), [`proposals/key-lanes.md`](../proposals/key-lanes.md), [`proposals/authorization-scopes.md`](../proposals/authorization-scopes.md).

```solidity
contract NonceLaneRegistry {
    mapping(address => mapping(uint256 => uint64)) private lanes;

    function check(address sender, uint256 key, uint64 seq) external view returns (bool);
    function advance(address sender, uint256 key) external;  // SYSTEM_ADDRESS only
    function get(address sender, uint256 key) external view returns (uint64);
}
```

### Pre-tx system call

```
if tx.nonce_key == 0:
    require tx.nonce == state[tx.sender].nonce
    state[tx.sender].nonce += 1
else:
    require REGISTRY.check(tx.sender, tx.nonce_key, tx.nonce)
    REGISTRY.advance(tx.sender, tx.nonce_key)
```

### State and cost

Lane state lives in `state[REGISTRY].storage`, keyed by standard nested-mapping layout. Witnesses are standard storage proofs against the registry's `storageRoot`. Verkle / state-tree transition inherits from contract storage.

First-use cost of a non-zero lane is SSTORE-from-zero (20 000 gas with EIP-2929 refinements). No separate `LANE_ALLOCATION_COST` constant. Pruning / reclamation is v2.

## 2. PubkeyRegistry

Holds per-account `(scheme_id, pubkey_bytes)` for PQ accounts. Used by [`proposals/signer-binding.md`](../proposals/signer-binding.md), [`proposals/key-lanes.md`](../proposals/key-lanes.md), [`proposals/authorization-scopes.md`](../proposals/authorization-scopes.md). The verified-signers table that consumes this state is specified in [`appendix/verified-signers.md`](verified-signers.md).

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

### State and cost

Registration is SSTORE-from-zero plus pubkey calldata. Clearing is SSTORE-to-zero. Accounts self-register via an EIP-8141 SENDER frame; the protocol does not auto-register.

Inline envelope pubkeys are explicitly rejected. For lattice and multivariate schemes, kilobyte-scale pubkeys make per-tx inlining impractical. For hash-based (SLH-DSA: 32-64 B) the size case doesn't hold, but supporting both pubkey-by-reference and pubkey-by-value forks the protocol into two binding chains for one logical capability. Registry-only is uniform across families and avoids a second binding/sighash conversation. See [`appendix/pq-analysis.md`](pq-analysis.md).

## 3. Common deployment model

Both contracts share:

- **Reserved address**, upgrade-coordinated.
- **Immutable**: address + expected code hash pinned by consensus; default code verifies the code hash before any system call.
- **Upgrades** ship as new reserved addresses at future upgrades. Existing state stays on the old address.
- **Why immutable**: matches the EIP-4788, EIP-2935, and ERC-4337 EntryPoint precedent. Avoids centralising upgrade authority. Migration is explicit and user-visible. Existing state stays valid against the registry it was written against. Prevents rug-pull scenarios.

## 4. Why system contracts and not account-encoding fields

An earlier flexible-nonces draft proposed adding a `lanesRoot` field to the account RLP encoding (the account 4-tuple: `nonce, balance, storageRoot, codeHash`). Rejected: changing account encoding ripples through every RLP parser, every state-root computation, EIP-161, archive-node decoding, and witness format. The system-contract pattern keeps the change at the storage layer where existing machinery already covers it: snap sync, witnesses, state-tree transitions, archive decoding all work without bespoke code paths.

By extension, PubkeyRegistry uses the same pattern. Storing a per-account PQ pubkey on the account record itself was never seriously considered for the same reasons, with the additional size problem for lattice and multivariate schemes (kilobyte-scale pubkeys would balloon the account RLP).

## 5. VOPS profile

State-growth budget is best-guess pending cross-client benchmarks. For NonceLaneRegistry: ~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate. PubkeyRegistry growth is bounded by one entry per registered account; PQ migrations are infrequent and pubkey calldata is the dominant cost.

VOPS slicing treats both registries' slots as ordinary storage witnesses. If growth exceeds budget, raise first-use cost via a standard SSTORE-accounting amendment.

## 6. Mempool admission

Both registries are restrictive-tier compatible:

- **NonceLaneRegistry**: one storage slot read per touched `(sender, nonce_key)` lane.
- **PubkeyRegistry**: one storage slot read per binding VERIFY frame.

Restrictive tier definitions live in [`appendix/mempool-tiers.md`](mempool-tiers.md).

## 7. RPC

```
eth_getTransactionCountByKey(address, nonce_key, blockTag) → uint64        // NonceLaneRegistry
eth_getRegisteredPubkey(address, blockTag)                 → (uint16, bytes) | null  // PubkeyRegistry
```

Error codes are listed per-proposal where they apply.

## 8. Spec delta summary

Per alternative that includes the relevant feature(s):

- Deploy `NonceLaneRegistry` (if flexible nonces): reserved address, immutable, code-hash pinned.
- Deploy `PubkeyRegistry` (if signer binding): reserved address, immutable, code-hash pinned.
- Pre-tx rule: non-zero `nonce_key` system-calls `NonceLaneRegistry.check` + `advance`; key 0 retains the legacy account-nonce path.
- VERIFY frames resolve PQ pubkeys via `PubkeyRegistry.get(frame.target)` during signer binding (semantics in [`appendix/verified-signers.md`](verified-signers.md)).

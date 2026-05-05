# Overview, Expanded EIP-8141

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 is the **native AA upgrade**: it lifts AA to the native protocol layer with a frame-based transaction model. This repo proposes an expansion of that upgrade.

The repo carries one consolidated proposal ([`/eip-8141.md`](../eip-8141.md), which executes Auth scopes) plus five alternative scopes preserved for comparison. The load-bearing-weight argument behind the chosen bundle, including which compromises are acceptable if scope must shrink, is in [`priorities.md`](priorities.md).

Status legend:

- **Current EIP-8141:** external upstream spec. See [eip8141.io Current Spec](https://eip8141.io/current-spec), [Merged Changes](https://eip8141.io/merged-changes), and the [EIP text](https://eips.ethereum.org/EIPS/eip-8141).
- **Guarantors:** companion feature in flight as [PR #11555](https://github.com/ethereum/EIPs/pull/11555); folded into the consolidated proposal here.
- **Flexible nonces, signer binding, validity windows:** the three additions on top.

Reader paths: core devs, [`/eip-8141.md`](../eip-8141.md) + [`compare.md`](compare.md) + referenced appendices. Wallet devs, README + priorities + proposal RPC/UX. Infra devs, mempool tiers + system contracts + RPC. App devs, proposal UX and compatibility.

## Expanded native AA upgrade

The proposals expand EIP-8141 rather than replace it. Every alternative includes:

- Current EIP-8141 (frame transactions, default code, five frame opcodes, restrictive mempool policy).
- **Guarantors** ([PR #11555](https://github.com/ethereum/EIPs/pull/11555)): payer primitive for txs whose sender validation may fail. Confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

Alternatives differ in which combination of three independent features is added on top:

- **Flexible nonces**, aka 2D nonces. Standalone: envelope `nonce_key` (uint256, `NonceManager`); aggregated: envelope `signer` (uint64, `AuthManager`) so the stream selector is the registered signer's id.
- **Signer binding** (registry-backed; `PubkeyRegistry` standalone or `AuthManager` aggregated; tx-scoped verified-signers table).
- **Validity windows** (envelope `valid_after`, `valid_before`).

| Alternative | Doc | Features | Registry |
|---|---|---|---|
| Flexible nonces | [`proposals/flexible-nonces.md`](proposals/flexible-nonces.md) | Flexible nonces | `NonceManager` |
| Signer binding | [`proposals/signer-binding.md`](proposals/signer-binding.md) | Signer binding | `PubkeyRegistry` |
| Validity windows | [`proposals/validity-windows.md`](proposals/validity-windows.md) | Validity windows | none |
| Key streams | [`proposals/key-streams.md`](proposals/key-streams.md) | Flexible nonces + signer binding | `AuthManager` |
| Auth scopes | [`proposals/auth-scopes.md`](proposals/auth-scopes.md) | Flexible nonces + signer binding + validity windows | `AuthManager` |

The consolidated [`/eip-8141.md`](../eip-8141.md) is the PR-shaped execution of Auth scopes; the aggregated proposals collapse the two standalone registries into a single `AuthManager`. See [`appendix/system-contracts.md`](appendix/system-contracts.md) for the contract specs and [`compare.md`](compare.md) for the delta map.

### Contract requirements per alternative

Each alternative deploys exactly the contracts it requires:

- Validity windows: none (envelope-only).
- Flexible nonces: `NonceManager` (constant `NONCE_MANAGER`).
- Signer binding: `PubkeyRegistry` (constant `PUBKEY_REGISTRY`).
- Key streams: `AuthManager` (constant `AUTH_MANAGER`); merges `NonceManager` + `PubkeyRegistry`.
- Auth scopes: `AuthManager`; validity windows add no contract.

## Per-alternative analysis

### Flexible nonces

**Protocol surface**: 1 envelope field (`nonce_key`), 1 system contract (`NonceManager`), 1 pre-tx system call, per-stream mempool rules, `eth_getTransactionCountByKey`.

**Core-dev**: clean precedent (EIP-4788, EIP-2935). State-growth bounded by SSTORE cost + mempool caps. FOCIL needs cross-client tests on per-stream RBF.

**User impact**: solves stuck txs for EOAs; supports nullifier-as-nonce for native accounts; makes parallel guarantor sponsorship tractable. Universal EOA coverage on activation day.

**What it leaves on the table**: PQ accounts still locked out of immutable `ECRECOVER` callers; signature staleness unaddressed.

### Signer binding

**Protocol surface**: 1 system contract (`PubkeyRegistry`), tx-scoped verified-signers table, `ECRECOVER` hit-path-first lookup, RPC additions, `MAX_BOUND_SIGNERS = 8` cap.

**Core-dev**: no envelope changes, no opcodes, no precompile changes. `ECRECOVER` miss-path byte-identical. Restrictive-tier admission is one storage slot read.

**User impact**: PQ accounts work with existing immutable contracts (`permit`, WETH, Uniswap V2 pairs). Closes the "EIP-8141 doesn't actually fix PQ for existing contracts" gap.

**What it leaves on the table**: stuck-tx problem and signature staleness untouched.

### Validity windows

**Protocol surface**: 2 envelope fields (`valid_after`, `valid_before`), 1 pre-tx time check. No state, no contracts.

**Core-dev**: smallest possible change in this set. Envelope-only, deterministic, FOCIL-friendly, zero VOPS impact.

**User impact**: swaps expire, scheduled txs activate, stale-signature attacks closed. Native expiry day one.

**What it leaves on the table**: stuck-tx problem and PQ-recovery gap untouched.

### Key streams (Flexible nonces + signer binding)

**Protocol surface**: 1 envelope field, 1 system contract (`AuthManager`, holding both nonce streams and signer entries), 1 pre-tx system call, RPC additions, `ECRECOVER` extension, joint mempool caps.

**Core-dev**: same EIP-4788 system-contract pattern; merged `AuthManager` collapses two registries into one address and one code-hash; same restrictive-tier reasoning; one upgrade's review effort instead of two.

**User impact**: stuck-tx problem solved and PQ accounts unblocked for legacy `ECRECOVER`. Signature staleness still unaddressed.

**Resilience**: either component pull-able without invalidating the other; the nonce and signer halves of `AuthManager` do not cross-reference at the storage layer.

### Auth scopes (all three)

**Protocol surface**: 3 envelope fields, 1 system contract (`AuthManager`), 1 pre-tx system call + 1 pre-tx time check, RPC additions, `ECRECOVER` extension, joint mempool rules.

**Core-dev**: largest alternative. Three orthogonal features sharing one upgrade's review. Cross-proposal interactions need cross-client tests.

**User impact**: complete vocabulary across stream, time, and subject dimensions. No stuck txs, no stale sigs, PQ accounts unblocked.

**Resilience**: any of the three pull-able without invalidating the other two.

**Reference execution**: [`/eip-8141.md`](../eip-8141.md) is the consolidated EIP draft for this bundle; reference contracts under [`assets/eip-8141/`](../assets/eip-8141/).

## Comparison

| | Flexible nonces | Signer binding | Validity windows | Key streams | Auth scopes |
|---|---|---|---|---|---|
| New envelope fields | 1 | 0 | 2 | 1 | 3 |
| New system contracts | 1 (`NonceManager`) | 1 (`PubkeyRegistry`) | 0 | 1 (`AuthManager`) | 1 (`AuthManager`) |
| New tx-scoped state | 1 (guarantor) | 1 (guarantor) + verified-signers table | 1 (guarantor) | 1 (guarantor) + verified-signers table | 1 (guarantor) + verified-signers table |
| Pre-tx checks added | 1 (stream) | 0 (validation-time) | 1 (window) | 1 (stream) | 2 (stream + window) |
| `ECRECOVER` extended? | no | yes (hit-path-first) | no | yes | yes |
| Mempool policy additions | per-stream RBF, stream caps | binding cap | tiered window deferral | per-stream RBF, stream + binding caps | per-stream RBF, stream + window + binding caps |
| RPC additions | `eth_getTransactionCountByKey` | `eth_getRegisteredPubkey`, `eth_simulateSignerBinding` | 4 error codes | nonce + binding RPCs | nonce + binding + 10 error codes |
| Account-encoding changes | 0 | 0 | 0 | 0 | 0 |
| Core-invariant changes | 0 | 0 | 0 | 0 | 0 |
| New opcodes | 0 | 0 | 0 | 0 | 0 |
| New precompiles | 0 | 0 | 0 | 0 | 0 |

## What every alternative shares

Guarantors (PR #11555) in every column. Zero new opcodes, precompiles, account-encoding changes, or core-invariant changes. In aggregated alternatives, dropping one component does not invalidate the others. Each proposal ends with a compact EIP-ready delta.

## Test plan

- Cross-client consensus tests for envelope decoding, pre-tx checks, registry calls, verified-signer table lifecycle, and `ECRECOVER` hit/miss paths.
- Mempool replacement tests for `(sender, stream_selector, tx.nonce)`, future-valid replacement, expiry eviction, and block-invalidation after stream advancement.
- FOCIL inclusion tests for restrictive-tier admissibility, future-valid deferral, expired-tx rejection, and attester-visible invariants.
- RPC compatibility tests for legacy `eth_getTransactionCount`, added nonce/pubkey RPCs, validity-window error codes, and byte-identical `ECRECOVER` miss-path.

## How to choose

The consolidated [`/eip-8141.md`](../eip-8141.md) ships Auth scopes as the default bundle; alternatives are preserved as the comparison surface and as compromise paths. Weights to consider:

- Core-dev review burden absorbable in one cycle.
- Urgency of each user-visible problem (stuck txs vs. PQ migration vs. stale sigs).
- Resilience to any one feature being pulled late.
- "Smallest reviewable change that helps" vs. "most user-visible delta we can credibly ship".

[`priorities.md`](priorities.md) argues Auth scopes as the default with Key streams and Signer binding as defensible compromises; standalone Flexible nonces and Validity windows are ruled out under the one-upgrade constraint.

## Design discipline

No new opcodes beyond the current EIP-8141 set. No new precompiles. No account-encoding changes. EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state. Crypto-agnostic interfaces; curve-specific data confined to [`appendix/pq-analysis.md`](appendix/pq-analysis.md).

## Open uncertainties

One item remains best-guess pending data; it does not block a proposal landing.

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for keyed-nonce storage (`NonceManager` standalone or the nonce side of `AuthManager` aggregated) | Back-of-envelope math (~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate). Needs cross-client benchmarks. Applies to any alternative including Flexible nonces. |

Flagged in the proposals where it applies; this section keeps it visible to a reviewer skimming the overview.

# Overview, Expanded EIP-8141

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 is the **native AA upgrade**: it lifts AA to the native protocol layer with a frame-based transaction model. This repo proposes an expansion of that upgrade.

The repo carries one consolidated proposal ([`/eip-8141.md`](../eip-8141.md), which executes Auth scopes) plus six alternative scopes preserved for comparison. The load-bearing-weight argument behind the chosen bundle, including which compromises are acceptable if scope must shrink, is in [`priorities.md`](priorities.md).

Status legend:

- **Current EIP-8141:** external upstream spec. See [eip8141.io Current Spec](https://eip8141.io/current-spec), [Merged Changes](https://eip8141.io/merged-changes), and the [EIP text](https://eips.ethereum.org/EIPS/eip-8141).
- **Guarantors:** companion in flight as [PR #11555](https://github.com/ethereum/EIPs/pull/11555); folded in here.
- **Flexible nonces, signer binding, envelope expiry:** the three additions on top. Validity windows is the two-sided sibling alternative to Envelope expiry, preserved for comparison.

Reader paths: core devs, [`/eip-8141.md`](../eip-8141.md) + [`compare.md`](compare.md) + referenced appendices. Wallet devs, README + priorities + proposal RPC/UX. Infra devs, mempool tiers + system contracts + RPC. App devs, proposal UX and compatibility.

## Expanded native AA upgrade

The proposals expand EIP-8141 rather than replace it. Every alternative includes:

- Current EIP-8141 (frame transactions, default code, five frame opcodes, restrictive mempool policy).
- **Guarantors** ([PR #11555](https://github.com/ethereum/EIPs/pull/11555)): payer primitive for txs whose sender validation may fail. Confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

Alternatives differ in which combination of three independent features is added on top:

- **Flexible nonces**, aka 2D nonces. Standalone: envelope `nonce_key` (uint256, `NonceManager`); aggregated: envelope `signer` (uint64, `AuthManager`).
- **Signer binding** (registry-backed; `PubkeyRegistry` standalone or `AuthManager` aggregated; tx-scoped verified-signers table).
- **Time-bound transactions.** Two mutually-exclusive shapes: **Validity windows** (`valid_after` + `valid_before`) and **Envelope expiry** (one-sided `expiry`). Auth scopes folds in Envelope expiry; trade-off in [`priorities.md`](priorities.md).

| Alternative | Doc | Features | Registry |
|---|---|---|---|
| Flexible nonces | [`proposals/flexible-nonces.md`](proposals/flexible-nonces.md) | Flexible nonces | `NonceManager` |
| Signer binding | [`proposals/signer-binding.md`](proposals/signer-binding.md) | Signer binding | `PubkeyRegistry` |
| Validity windows | [`proposals/validity-windows.md`](proposals/validity-windows.md) | `valid_after` + `valid_before` | none |
| Envelope expiry | [`proposals/envelope-expiry.md`](proposals/envelope-expiry.md) | One-sided `expiry` | none |
| Key streams | [`proposals/key-streams.md`](proposals/key-streams.md) | Flexible nonces + signer binding | `AuthManager` |
| Auth scopes | [`proposals/auth-scopes.md`](proposals/auth-scopes.md) | Flexible nonces + signer binding + envelope expiry | `AuthManager` |

The consolidated [`/eip-8141.md`](../eip-8141.md) is the PR-shaped execution of Auth scopes; the aggregated proposals collapse the two standalone registries into a single `AuthManager`. See [`appendix/system-contracts.md`](appendix/system-contracts.md) for the contract specs and [`compare.md`](compare.md) for the delta map.

### Contract requirements per alternative

Each alternative deploys exactly the contracts it requires:

- Validity windows, Envelope expiry: none (envelope-only).
- Flexible nonces: `NonceManager` (`NONCE_MANAGER`).
- Signer binding: `PubkeyRegistry` (`PUBKEY_REGISTRY`).
- Key streams, Auth scopes: `AuthManager` (`AUTH_MANAGER`), merging `NonceManager` + `PubkeyRegistry`.

## Per-alternative analysis

### Flexible nonces

**Protocol surface**: 1 envelope field (`nonce_key`), 1 system contract (`NonceManager`), 1 pre-tx system call, per-stream mempool rules, `eth_getTransactionCountByKey`. Clean precedent (EIP-4788, EIP-2935); state-growth bounded by SSTORE cost + mempool caps; FOCIL needs cross-client tests on per-stream RBF.

**User impact**: solves stuck txs for EOAs; supports nullifier-as-nonce for native accounts; makes parallel guarantor sponsorship tractable. Universal EOA coverage on activation day. PQ accounts still locked out of immutable `ECRECOVER` callers; signature staleness unaddressed.

### Signer binding

**Protocol surface**: 1 system contract (`PubkeyRegistry`), tx-scoped verified-signers table, `ECRECOVER` hit-path-first lookup, RPC additions, `MAX_BOUND_SIGNERS = 8` cap. No envelope changes, no opcodes; `ECRECOVER` miss-path byte-identical; restrictive-tier admission is one storage slot read.

**User impact**: PQ accounts work with existing immutable contracts (`permit`, WETH, Uniswap V2 pairs). Closes the "EIP-8141 doesn't fix PQ for existing contracts" gap. Stuck-tx and signature-staleness gaps untouched.

### Validity windows

**Protocol surface**: 2 envelope fields (`valid_after`, `valid_before`), pre-tx time check on both bounds + reverse-window rejection, future-valid mempool buffer with deferral horizon and gossip threshold, four error codes. Envelope-only and FOCIL-friendly; mempool policy non-trivial.

**User impact**: intent deadlines plus native scheduled activation (signed tx held by nodes until `valid_after`). Stuck-tx and PQ-recovery gaps untouched. Mutually exclusive with Envelope expiry.

### Envelope expiry

**Protocol surface**: 1 envelope field (`expiry`), 1 pre-tx time check, two error codes. No state, no contracts, no future-valid mempool state. Strict subset of Validity windows; smallest change in the set.

**User impact**: intent flows (signed-order DEXes, bridges, RFQ aggregators, gasless swaps) get consensus-enforced deadlines, ending reliance on filler timing. Trading and atomic-swap deadlines land in the same primitive. Scheduled activation deferred offchain; head-to-head rationale in [`proposals/envelope-expiry.md`](proposals/envelope-expiry.md) §3.

### Key streams (Flexible nonces + signer binding)

**Protocol surface**: 1 envelope field, 1 system contract (`AuthManager`, holding both nonce streams and signer entries), 1 pre-tx system call, RPC additions, `ECRECOVER` extension, joint mempool caps. Merged `AuthManager` collapses two registries into one address and code-hash; one upgrade's review effort instead of two.

**User impact**: stuck-tx problem solved and PQ accounts unblocked for legacy `ECRECOVER`. Signature staleness still unaddressed. Either component pull-able without invalidating the other.

### Auth scopes (Flexible nonces + signer binding + envelope expiry)

**Protocol surface**: 2 envelope fields, 1 system contract (`AuthManager`), 1 pre-tx system call + 1 pre-tx time check, RPC additions, `ECRECOVER` extension, joint mempool rules. Largest alternative; three orthogonal features sharing one upgrade's review.

**User impact**: complete vocabulary across stream, time, and subject dimensions. No stuck txs, no stale sigs, PQ accounts unblocked. Any of the three pull-able without invalidating the other two.

**Reference execution**: [`/eip-8141.md`](../eip-8141.md) is the consolidated EIP draft; reference contracts under [`assets/eip-8141/`](../assets/eip-8141/).

## Comparison

| | Flexible nonces | Signer binding | Validity windows | Envelope expiry | Key streams | Auth scopes |
|---|---|---|---|---|---|---|
| New envelope fields | 1 | 0 | 2 | 1 | 1 | 2 |
| New system contracts | 1 (`NonceManager`) | 1 (`PubkeyRegistry`) | 0 | 0 | 1 (`AuthManager`) | 1 (`AuthManager`) |
| Pre-tx checks added | 1 (stream) | 0 (validation-time) | 1 (both + reverse) | 1 (expiry) | 1 (stream) | 2 (stream + expiry) |
| `ECRECOVER` extended? | no | yes | no | no | yes | yes |
| Mempool additions | per-stream RBF | binding cap | future-valid buffer + gossip threshold + expired eviction | expired eviction | per-stream RBF + binding cap | per-stream RBF + expiry + binding cap |
| RPC additions | `eth_getTransactionCountByKey` | `eth_getRegisteredPubkey`, `eth_simulateSignerBinding` | 4 error codes | 2 error codes | nonce + binding RPCs | nonce + binding + 8 error codes |
| Account-encoding / opcodes / precompiles | 0 | 0 | 0 | 0 | 0 | 0 |

## What every alternative shares

Guarantors (PR #11555) in every column. Zero new opcodes, precompiles, account-encoding, or core-invariant changes. Each proposal ends with a compact EIP-ready delta.

## Test plan

- Cross-client consensus tests for envelope decoding, pre-tx checks, registry calls, verified-signer table lifecycle, `ECRECOVER` paths.
- Mempool replacement tests for `(sender, stream_selector, tx.nonce)`, expiry-aware RBF, expired eviction, and block-invalidation after stream advancement.
- FOCIL inclusion tests for restrictive-tier admissibility, expired-tx rejection, attester-visible invariants.
- RPC compatibility tests for legacy `eth_getTransactionCount`, added nonce/pubkey RPCs, expiry error codes, byte-identical `ECRECOVER` miss-path.

Validity windows additionally requires tests for future-valid buffering, gossip-threshold release, and reverse-window rejection; not needed for the consolidated draft.

## How to choose

The consolidated [`/eip-8141.md`](../eip-8141.md) ships Auth scopes as the default bundle; alternatives are preserved as comparison surface and compromise paths. Weights: core-dev review burden in one cycle, urgency of each user-visible problem, resilience to any one feature being pulled late, smallest reviewable change vs. largest user-visible delta credibly shippable.

[`priorities.md`](priorities.md) argues Auth scopes as default with Key streams and Signer binding as defensible compromises; standalone Flexible nonces, Validity windows, and Envelope expiry are ruled out under the one-upgrade constraint. The same doc argues Envelope expiry over Validity windows on cost-per-envelope-byte grounds.

## Design discipline

No new opcodes beyond the current EIP-8141 set; no precompiles; no account-encoding changes. EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state. Crypto-agnostic interfaces; curve-specific data confined to [`appendix/pq-analysis.md`](appendix/pq-analysis.md).

## Open uncertainties

One item remains best-guess pending data; it does not block a proposal landing.

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for keyed-nonce storage (`NonceManager` standalone or `AuthManager` nonce side aggregated) | Back-of-envelope (~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate). Needs cross-client benchmarks. Applies to any alternative with Flexible nonces. |

Flagged in the proposals where it applies; this section keeps it visible to a reviewer skimming the overview.

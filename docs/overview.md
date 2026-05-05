# Overview, Expanded EIP-8141

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 is the **native AA upgrade**: it lifts AA to the native protocol layer with a frame-based transaction model. This repo proposes an expansion of that upgrade.

The proposals are presented as five neutral alternatives with no recommended pick. The opinionated companion to this overview is [`priorities.md`](priorities.md), which ranks the alternatives by load-bearing weight under the one-upgrade constraint.

Status legend:

- **Current EIP-8141:** external upstream spec. See [eip8141.io Current Spec](https://eip8141.io/current-spec), [Merged Changes](https://eip8141.io/merged-changes), and the [EIP text](https://eips.ethereum.org/EIPS/eip-8141).
- **Guarantors:** pending companion feature, tracked separately and assumed to land in parallel.
- **Flexible nonces, signer binding, validity windows:** expansion proposals from this repo.

This repo is research and scope material intended to inform an EIP-8141 expansion. It is not itself the EIP text.

Reader paths: core devs, overview + selected proposal + referenced appendices. Wallet devs, README + priorities + proposal RPC/UX. Infra devs, mempool tiers + system contracts + RPC. App devs, proposal UX and compatibility.

## Expanded native AA upgrade

The proposals expand EIP-8141 rather than replace it. Every alternative includes:

- Current EIP-8141 (frame transactions, default code, five frame opcodes, restrictive mempool policy).
- **Guarantors** ([PR #11555](https://github.com/ethereum/EIPs/pull/11555)): draft payer primitive for txs whose sender validation may fail. Confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

Guarantors are not part of the current published EIP-8141 spec. They are pending, tracked separately, and assumed to land in parallel. They are shared context, not one of the three optional expansion features.

Alternatives differ only in which combination of three independent features is added on top:

- **Flexible nonces**, aka 2D nonces (envelope `nonce_key`, `NonceLaneRegistry`).
- **Signer binding** (registry-backed; `PubkeyRegistry`; tx-scoped verified-signers table).
- **Validity windows** (envelope `valid_after`, `valid_before`).

| Alternative | Doc | Features |
|---|---|---|
| Flexible nonces | [`proposals/flexible-nonces.md`](proposals/flexible-nonces.md) | Flexible nonces |
| Signer binding | [`proposals/signer-binding.md`](proposals/signer-binding.md) | Signer binding |
| Validity windows | [`proposals/validity-windows.md`](proposals/validity-windows.md) | Validity windows |
| Key lanes | [`proposals/key-lanes.md`](proposals/key-lanes.md) | Flexible nonces + signer binding |
| Authorization scopes | [`proposals/authorization-scopes.md`](proposals/authorization-scopes.md) | Flexible nonces + signer binding + validity windows |

## Per-alternative analysis

### Flexible nonces

**Protocol surface**: 1 envelope field (`nonce_key`), 1 system contract (`NonceLaneRegistry`), 1 pre-tx system call, per-lane mempool rules, `eth_getTransactionCountByKey`.

**Core-dev**: clean precedent (EIP-4788, EIP-2935). State-growth bounded by SSTORE cost + mempool caps. FOCIL needs cross-client tests on per-lane RBF.

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

### Key lanes (Flexible nonces + signer binding)

**Protocol surface**: 1 envelope field, 2 system contracts, 1 pre-tx system call, RPC additions, `ECRECOVER` extension, joint mempool caps.

**Core-dev**: same EIP-4788 system-contract pattern reused for both registries; same restrictive-tier reasoning; one upgrade's review effort instead of two.

**User impact**: stuck-tx problem solved and PQ accounts unblocked for legacy `ECRECOVER`. Signature staleness still unaddressed.

**Resilience**: either component pull-able without invalidating the other. They are pairwise orthogonal at the consensus rule level.

### Authorization scopes (all three)

**Protocol surface**: 3 envelope fields, 2 system contracts, 1 pre-tx system call + 1 pre-tx time check, RPC additions, `ECRECOVER` extension, joint mempool rules.

**Core-dev**: largest alternative. Three orthogonal features sharing one upgrade's review. Cross-proposal interactions need cross-client tests.

**User impact**: complete vocabulary across stream, time, and subject dimensions. No stuck txs, no stale sigs, PQ accounts unblocked.

**Resilience**: any of the three pull-able without invalidating the other two.

## Comparison

| | Flexible nonces | Signer binding | Validity windows | Key lanes | Authorization scopes |
|---|---|---|---|---|---|
| New envelope fields | 1 | 0 | 2 | 1 | 3 |
| New system contracts | 1 | 1 | 0 | 2 | 2 |
| New tx-scoped state | 1 (guarantor) | 1 (guarantor) + verified-signers table | 1 (guarantor) | 1 (guarantor) + verified-signers table | 1 (guarantor) + verified-signers table |
| Pre-tx checks added | 1 (lane) | 0 (validation-time) | 1 (window) | 1 (lane) | 2 (lane + window) |
| `ECRECOVER` extended? | no | yes (hit-path-first) | no | yes | yes |
| Mempool policy additions | per-lane RBF, lane caps | binding cap | tiered window deferral | per-lane RBF, lane + binding caps | per-lane RBF, lane + window + binding caps |
| RPC additions | `eth_getTransactionCountByKey` | `eth_getRegisteredPubkey`, `eth_simulateSignerBinding` | 4 error codes | nonce + binding RPCs | nonce + binding + 10 error codes |
| Account-encoding changes | 0 | 0 | 0 | 0 | 0 |
| Core-invariant changes | 0 | 0 | 0 | 0 | 0 |
| New opcodes | 0 | 0 | 0 | 0 | 0 |
| New precompiles | 0 | 0 | 0 | 0 | 0 |

## What every alternative shares

- **Guarantors** in every column: draft PR #11555 lands across the board.
- **Zero opcodes, precompiles, account-encoding changes, core-invariant changes**: every alternative respects the design principles in `CLAUDE.md`.
- **Resilience**: in any aggregated alternative, dropping one component does not invalidate the others; each feature stands on its own design.
- **EIP-ready delta**: each proposal ends with a compact section intended to be portable into a formal EIP PR.

Flexible nonces, Key lanes, and Authorization scopes are complementary to Guarantors: they reduce contention, isolate sponsorship flows, and bound authorization risk, which makes Guarantors more viable in public mempools.

## Test plan

- Cross-client consensus tests for envelope decoding, pre-tx checks, registry calls, verified-signer table lifecycle, and `ECRECOVER` hit and miss paths.
- Mempool replacement tests for `(sender, nonce_key, tx.nonce)`, future-valid replacement, expiry eviction, and block-invalidation after lane advancement.
- FOCIL inclusion tests for restrictive-tier admissibility, future-valid deferral, expired-tx rejection, and attester-visible invariants.
- RPC compatibility tests for legacy `eth_getTransactionCount`, added nonce and pubkey RPCs, validity-window error codes, and byte-identical `ECRECOVER` miss-path behavior.

## How to choose

This doc presents the five alternatives without picking. The choice depends on weights this overview doesn't take a position on:

- How much core-dev review burden the upgrade can absorb in one cycle.
- How urgent each user-visible problem is (stuck txs vs. PQ migration vs. stale signatures).
- How resilient the upgrade should be to any one feature being pulled late.
- Whether the upgrade goal is "smallest reviewable change that helps" or "most user-visible UX delta we can credibly ship".

Core devs and wallet devs decide the weights; any of the five alternatives is shippable.

## Design discipline

No new opcodes. No new precompiles. No account-encoding changes. EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state. Crypto-agnostic interfaces; curve-specific data confined to [`appendix/pq-analysis.md`](appendix/pq-analysis.md).

## Open uncertainties

One item remains best-guess pending data; it does not block a proposal landing.

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `NonceLaneRegistry` | Back-of-envelope math (~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate). Needs cross-client benchmarks. Applies to any alternative including Flexible nonces. |

Flagged in the proposals where it applies; this section keeps it visible to a reviewer skimming the overview.

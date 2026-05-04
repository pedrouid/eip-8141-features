# Overview, Expanded EIP-8141

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 is the **native AA upgrade**: it lifts AA to the native protocol layer with a frame-based transaction model. This repo proposes an expansion of that upgrade.

The proposals are presented as five neutral alternatives with no recommended pick. The opinionated companion to this overview is [`priorities.md`](priorities.md), which ranks the alternatives by load-bearing weight under the one-upgrade constraint.

## Expanded native AA upgrade

The proposals expand the scope of the existing EIP-8141 upgrade. They do not replace it; they ship alongside, adding guarantors plus a chosen subset of three independent features. Every alternative includes:

- Base EIP-8141 (frame transactions, default code, the existing `APPROVE` rule).
- **Guarantors** (PR #11555): `APPROVE(guarantee)` scope, tx-scoped `guarantor`, mempool relaxation. Confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

Alternatives differ only in which combination of three independent features is added on top:

- **N**: Flexible nonces, aka 2D nonces (envelope `nonce_key`, `NonceLaneRegistry`).
- **S**: Signer binding (registry-backed; `PubkeyRegistry`; tx-scoped verified-signers table).
- **W**: Validity windows (envelope `valid_after`, `valid_before`).

| ID | Doc | Features |
|---|---|---|
| **N** | [`proposals/flexible-nonces.md`](proposals/flexible-nonces.md) | Flexible nonces |
| **S** | [`proposals/signer-binding.md`](proposals/signer-binding.md) | Signer binding |
| **W** | [`proposals/validity-windows.md`](proposals/validity-windows.md) | Validity windows |
| **NS** | [`proposals/key-lanes.md`](proposals/key-lanes.md) | Flexible nonces + signer binding |
| **NSW** | [`proposals/authorization-scopes.md`](proposals/authorization-scopes.md) | Flexible nonces + signer binding + validity windows |

## Per-alternative analysis

### N, Flexible nonces

**Protocol surface**: 1 envelope field (`nonce_key`), 1 system contract (`NonceLaneRegistry`), 1 pre-tx system call, per-lane mempool rules, `eth_getTransactionCountByKey`.

**Core-dev**: clean precedent (EIP-4788, EIP-2935). State-growth bounded by SSTORE cost + mempool caps. FOCIL needs cross-client tests on per-lane RBF.

**User impact**: solves stuck-tx problem for EOAs; supports nullifier-as-nonce for native accounts (privacy pools, where a pool contract originates redemptions and each nullifier indexes its own stream); makes parallel guarantor sponsorship tractable. Universal EOA coverage on activation day.

**What it leaves on the table**: PQ accounts still locked out of immutable `ECRECOVER` callers; signature staleness unaddressed.

### S, signer binding

**Protocol surface**: 1 system contract (`PubkeyRegistry`), tx-scoped verified-signers table, `ECRECOVER` hit-path-first lookup, RPC additions, `MAX_BOUND_SIGNERS = 8` cap.

**Core-dev**: no envelope changes, no opcodes, no precompile changes. `ECRECOVER` miss-path byte-identical. Restrictive-tier admission is one storage slot read.

**User impact**: PQ accounts work with existing immutable contracts (`permit`, WETH, Uniswap V2 pairs). Closes the "EIP-8141 doesn't actually fix PQ for existing contracts" gap.

**What it leaves on the table**: stuck-tx problem and signature staleness untouched.

### W, validity windows

**Protocol surface**: 2 envelope fields (`valid_after`, `valid_before`), 1 pre-tx time check. No state, no contracts.

**Core-dev**: smallest possible change in this set. Envelope-only, deterministic, FOCIL-friendly, zero VOPS impact.

**User impact**: swaps expire, scheduled txs activate, stale-signature attacks closed. Native expiry day one.

**What it leaves on the table**: stuck-tx problem and PQ-recovery gap untouched.

### NS, key lanes (Flexible nonces + signer binding)

**Protocol surface**: 1 envelope field, 2 system contracts, 1 pre-tx system call, RPC additions, `ECRECOVER` extension, joint mempool caps.

**Core-dev**: same EIP-4788 system-contract pattern reused for both registries; same restrictive-tier reasoning; one upgrade's review effort instead of two.

**User impact**: stuck-tx problem solved and PQ accounts unblocked for legacy `ECRECOVER`. Signature staleness still unaddressed.

**Resilience**: either component pull-able without invalidating the other. They are pairwise orthogonal at the consensus rule level.

### NSW, authorization scopes (all three)

**Protocol surface**: 3 envelope fields, 2 system contracts, 1 pre-tx system call + 1 pre-tx time check, RPC additions, `ECRECOVER` extension, joint mempool rules.

**Core-dev**: largest alternative. Three orthogonal features sharing one upgrade's review. Cross-proposal interactions (future-valid tx reserving its lane, RBF across `(sender, nonce_key, tx.nonce)` with window constraints, signer binding during a future-valid tx) need cross-client tests.

**User impact**: complete vocabulary across stream, time, and subject dimensions. No stuck txs, no stale sigs, PQ accounts unblocked.

**Resilience**: any of the three pull-able without invalidating the other two.

## Comparison

| | N | S | W | NS | NSW |
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

- **Guarantors** in every column: PR #11555 lands across the board.
- **Zero opcodes, precompiles, account-encoding changes, core-invariant changes**: every alternative respects the design principles in `CLAUDE.md`.
- **Resilience**: in any aggregated alternative, dropping one component does not invalidate the others; each feature stands on its own design.

## How to choose

This doc deliberately presents the five alternatives without picking. The choice depends on weights this overview doesn't take a position on:

- How much core-dev review burden the upgrade can absorb in one cycle.
- How urgent each user-visible problem is (stuck txs vs. PQ migration vs. stale signatures).
- How resilient the upgrade should be to any one feature being pulled late.
- Whether the upgrade goal is "smallest reviewable change that helps" (W or N) or "most user-visible UX delta we can credibly ship" (NSW).

Core devs and wallet devs reading this doc decide the weights; the proposals are designed so that any of the five alternatives is shippable.

## Design discipline

No new opcodes. No new precompiles. No account-encoding changes. EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state. Crypto-agnostic interfaces; curve-specific data confined to [`appendix/pq-analysis.md`](appendix/pq-analysis.md).

## Open uncertainties

One item remains best-guess pending data; it does not block a proposal landing.

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `NonceLaneRegistry` | Back-of-envelope math (~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate). Needs cross-client benchmarks. Applies to any alternative including Flexible nonces (N, NS, NSW). |

Flagged in the proposals where it applies; this section keeps it visible to a reviewer skimming the overview.

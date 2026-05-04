# Overview — Phased Expansion of EIP-8141

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 is the **native AA upgrade**: it lifts AA to the native protocol layer with a frame-based transaction model. This repo proposes an expansion of that upgrade in two phases.

Phase 1 is presented as five neutral alternatives with no recommended pick; Phase 2 is a separate follow-on upgrade and is not weighed against any Phase-1 alternative. The opinionated companion to this overview is [`priorities.md`](priorities.md), which ranks the alternatives by load-bearing weight under the one-upgrade constraint.

## Phase 1: expanded native AA upgrade

**Phase 1 expands the scope of the existing EIP-8141 upgrade.** It does not replace it; it ships alongside, adding guarantors plus a chosen subset of three independent features. Every Phase-1 alternative includes:

- Base EIP-8141 (frame transactions, default code, the existing `APPROVE` rule).
- **Guarantors** (PR #11555): `APPROVE(guarantee)` scope, tx-scoped `guarantor`, mempool relaxation. Confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

Alternatives differ only in which combination of three independent features is added on top:

- **N**: 2D nonces (envelope `nonce_key`, `NonceLaneRegistry`).
- **S**: Signer binding (registry-backed; `PubkeyRegistry`; tx-scoped verified-signers table).
- **W**: Validity windows (envelope `valid_after`, `valid_before`).

| ID | Doc | Features |
|---|---|---|
| **P1.N** | [`phase-1/2d-nonces.md`](phase-1/2d-nonces.md) | 2D nonces |
| **P1.S** | [`phase-1/signer-binding.md`](phase-1/signer-binding.md) | Signer binding |
| **P1.W** | [`phase-1/validity-windows.md`](phase-1/validity-windows.md) | Validity windows |
| **P1.NS** | [`phase-1/key-lanes.md`](phase-1/key-lanes.md) | 2D nonces + signer binding |
| **P1.NSW** | [`phase-1/authorization-scopes.md`](phase-1/authorization-scopes.md) | 2D nonces + signer binding + validity windows |

## Per-alternative analysis

### P1.N — 2D nonces

**Protocol surface**: 1 envelope field (`nonce_key`), 1 system contract (`NonceLaneRegistry`), 1 pre-tx system call, per-lane mempool rules, `eth_getTransactionCountByKey`.

**Core-dev**: clean precedent (EIP-4788, EIP-2935). State-growth bounded by SSTORE cost + mempool caps. FOCIL needs cross-client tests on per-lane RBF.

**User impact**: solves stuck-tx problem for every EOA. Universal coverage on activation day.

**What it leaves on the table**: PQ accounts still locked out of immutable `ECRECOVER` callers; signature staleness unaddressed.

### P1.S — Signer binding

**Protocol surface**: 1 system contract (`PubkeyRegistry`), tx-scoped verified-signers table, `ECRECOVER` hit-path-first lookup, RPC additions, `MAX_BOUND_SIGNERS = 8` cap.

**Core-dev**: no envelope changes, no opcodes, no precompile changes. `ECRECOVER` miss-path byte-identical. Restrictive-tier admission is one storage slot read.

**User impact**: PQ accounts work with existing immutable contracts (`permit`, WETH, Uniswap V2 pairs). Closes the "EIP-8141 doesn't actually fix PQ for existing contracts" gap.

**What it leaves on the table**: stuck-tx problem and signature staleness untouched.

### P1.W — Validity windows

**Protocol surface**: 2 envelope fields (`valid_after`, `valid_before`), 1 pre-tx time check. No state, no contracts.

**Core-dev**: smallest possible change in this set. Envelope-only, deterministic, FOCIL-friendly, zero VOPS impact.

**User impact**: swaps expire, scheduled txs activate, stale-signature attacks closed. Native expiry day one.

**What it leaves on the table**: stuck-tx problem and PQ-recovery gap untouched.

### P1.NS — Key lanes (2D nonces + signer binding)

**Protocol surface**: 1 envelope field, 2 system contracts, 1 pre-tx system call, RPC additions, `ECRECOVER` extension, joint mempool caps.

**Core-dev**: same EIP-4788 system-contract pattern reused for both registries; same restrictive-tier reasoning; one upgrade's review effort instead of two.

**User impact**: stuck-tx problem solved and PQ accounts unblocked for legacy `ECRECOVER`. Signature staleness still unaddressed.

**Resilience**: either component pull-able without invalidating the other. They are pairwise orthogonal at the consensus rule level.

### P1.NSW — Authorization scopes (all three)

**Protocol surface**: 3 envelope fields, 2 system contracts, 1 pre-tx system call + 1 pre-tx time check, RPC additions, `ECRECOVER` extension, joint mempool rules.

**Core-dev**: largest Phase-1 alternative. Three orthogonal features sharing one upgrade's review. Cross-proposal interactions (future-valid tx reserving its lane, RBF across `(sender, nonce_key, tx.nonce)` with window constraints, signer binding during a future-valid tx) need cross-client tests.

**User impact**: complete Phase-1 vocabulary across stream, time, and subject dimensions. No stuck txs, no stale sigs, PQ accounts unblocked.

**Resilience**: any of the three pull-able without invalidating the other two.

## Comparison

| | P1.N | P1.S | P1.W | P1.NS | P1.NSW |
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
- **Phase-2 independence**: every alternative is consistent with Phase 2 (permissions) shipping later as a separate EIP, regardless of which Phase-1 alternative landed.

## Phase 2: delegated permissions (follow-on upgrade)

ERC-7710/7715-style delegated permissions, depending on a standalone `execution-authority` EIP. Phase 2 is a follow-on upgrade, not part of the Phase-1 activation. **Stretch:** Phase 1 is already a substantial upgrade; bundling permissions on top is not recommended. Phase 2 ships once a Phase-1 alternative has landed and stabilised.

[`phase-2/permissions.md`](phase-2/permissions.md) lays out why bundling permissions with any Phase-1 alternative is not recommended: SENDER-frame `msg.sender` rule changes, default-code surface expansions, an additional system contract (`DelegationManager`), canonical caveat vocabulary, and PQ-migration complexity all add up to an upgrade that is substantial on its own. Phase 1 is already substantial; doubling up risks both.

Different Phase-1 alternatives change how much of the eventual permissions UX is achievable in software in the meantime, but none of them precludes Phase 2, and none of them obligates Phase 2 either. The decision on Phase 2 is independent.

See [`phase-2/permissions.md`](phase-2/permissions.md) and [`phase-2/execution-authority.md`](phase-2/execution-authority.md).

## How to choose

This doc deliberately presents the five Phase-1 alternatives without picking. The choice depends on weights this overview doesn't take a position on:

- How much core-dev review burden the upgrade can absorb in one cycle.
- How urgent each user-visible problem is (stuck txs vs. PQ migration vs. stale signatures).
- How resilient the upgrade should be to any one feature being pulled late.
- Whether the upgrade goal is "smallest reviewable change that helps" (P1.W or P1.N) or "most user-visible UX delta we can credibly ship" (P1.NSW).

Core devs and wallet devs reading this doc decide the weights; the proposals are designed so that any of the five alternatives is shippable.

## Design discipline (both phases)

No new opcodes. No new precompiles. No account-encoding changes. EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state. Crypto-agnostic interfaces; curve-specific data confined to [`appendix/pq-analysis.md`](appendix/pq-analysis.md).

## Open uncertainties

Two items remain best-guess pending data; neither blocks a proposal landing.

| # | Question | Status |
|---|---|---|
| Q6 | VOPS state-growth budget for `NonceLaneRegistry` | Back-of-envelope math (~2 GB/year legitimate; ~1 GB/day adversarial cap before SSTORE-from-zero + mempool caps saturate). Needs cross-client benchmarks. Applies to any alternative including 2D nonces (P1.N, P1.NS, P1.NSW). |
| Q12 | Size caps (proof / caveat / bundle) for Phase-2 permissions | PQ signature landscape still evolving. The `MAX_PROOF_SIZE = 8192` pick is reasonable for lattice schemes + classical hybrids, under-spec for hash-based at L3+. See [`appendix/pq-analysis.md`](appendix/pq-analysis.md). Phase-2 only. |

Both are flagged in the proposals where they apply; this section keeps them visible to a reviewer skimming the overview.

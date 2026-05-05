# EIP-8141 Upgrade

A proposal to expand the scope of [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md) (Frame Transaction), the **native account-abstraction upgrade** for Ethereum. Bundles guarantors and a chosen subset of three independent features into the same activation, on the basis that EIP-8141 is the one realistic opportunity to lift AA into the protocol layer.

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 lifts AA to the native protocol layer with a frame-based transaction model. This repo argues that the upgrade should land doing more than the minimum, since there will not be a second pass; the proposals expand its scope and have been iterated against core dev and wallet dev review pressure.

---

## How to review this repo

This repo is research and scope material intended to inform an EIP-8141 expansion. It is not itself the EIP text.

- **Core devs:** read `docs/overview.md`, then the selected proposal, then the appendix specs it references.
- **Wallet devs:** read this README, `docs/priorities.md`, and the proposal RPC and wallet UX sections.
- **Infra devs:** read `docs/appendix/mempool-tiers.md`, `docs/appendix/system-contracts.md`, and the proposal RPC sections.
- **App devs:** read the proposal wallet UX and compatibility sections.

Terminology used across the docs is defined once in `docs/glossary.md`.

---

## TL;DR

Status legend:

- **Base EIP-8141:** external upstream spec.
- **Guarantors:** pending companion feature, tracked separately and assumed to land in parallel.
- **Flexible nonces, signer binding, validity windows:** expansion proposals from this repo.

Guarantors are not part of the current published EIP-8141 spec. They are a pending companion feature, tracked separately, and this repo assumes they land in parallel with whichever expansion alternative is selected.

The proposals expand the scope of the existing EIP-8141 upgrade. They ship in the same activation as EIP-8141, adding guarantors as baseline context plus a chosen subset of three independent expansion features:

- **Flexible nonces**, protocol-native parallel nonce streams.
- **Signer binding**, registry-backed PQ identity for `ECRECOVER` callers.
- **Validity windows**, envelope-level `valid_after` / `valid_before` time bounds.

The proposals are presented as **five neutral alternatives**: three individual and two aggregated. No alternative is recommended; the choice is a tradeoff this repo does not take a position on.

| Alternative | Doc | Features bundled |
|---|---|---|
| Flexible nonces | `docs/proposals/flexible-nonces.md` | Flexible nonces |
| Signer binding | `docs/proposals/signer-binding.md` | Signer binding |
| Validity windows | `docs/proposals/validity-windows.md` | Validity windows |
| Key lanes | `docs/proposals/key-lanes.md` | Flexible nonces + signer binding |
| Authorization scopes | `docs/proposals/authorization-scopes.md` | Flexible nonces + signer binding + validity windows |

Every alternative ships guarantors (PR #11555) as the small mempool primitive that confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

Flexible nonces, Key lanes, and Authorization scopes are complementary to Guarantors: they reduce contention, isolate sponsorship flows, and bound authorization risk, which makes Guarantors more viable in public mempools.

See [`docs/overview.md`](docs/overview.md) for the per-alternative analysis and open uncertainties. See [`docs/priorities.md`](docs/priorities.md) for the opinionated take on which bundles are viable under the one-upgrade constraint.

---

## Repository structure

```
docs/
├── overview.md             # Read first; covers scope, the five alternatives, and tradeoffs
├── priorities.md           # Subjective companion; ranks bundles under the one-upgrade constraint
├── glossary.md             # Single canonical definition per term
│
├── proposals/              # Pick one alternative
│   ├── flexible-nonces.md            # Individual: Flexible nonces
│   ├── signer-binding.md       # Individual: registry-backed PQ identity
│   ├── validity-windows.md     # Individual: envelope time bounds
│   ├── key-lanes.md            # Aggregated: Flexible nonces + signer binding
│   └── authorization-scopes.md # Aggregated: Flexible nonces + signer binding + validity windows
│
└── appendix/               # Cross-cutting primitives, shared specs, and grounding analyses
    ├── guarantors.md           # APPROVE(guarantee), in every alternative
    ├── sighash-binding.md      # Class A/B binding analysis
    ├── system-contracts.md     # NonceLaneRegistry + PubkeyRegistry: shared spec
    ├── verified-signers.md     # Verified-signers table + modified ECRECOVER: shared spec
    ├── mempool-tiers.md        # Restrictive / expansive / private tier semantics
    └── pq-analysis.md          # NIST PQC + MAYO sizing; reth pipeline grounding
```

---

## Design principles

Principles every proposal follows. Deviations require explicit justification.

### Consensus-level minimalism

- No new opcodes.
- No new precompiles.
- No account-encoding changes; use the EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state.
- No core-invariant changes. Changes to SENDER-frame `msg.sender` semantics, fundamental APPROVE rules, or nonce consumption are out of scope.

### First-class EIP-8141 primitives

- Don't inherit from contract-era ERCs. ERC-4337 makes compromises (192-bit key packing, bundler enforcement, `isValidSignature` naming) because it lives above the protocol. EIP-8141 has the freedom to choose better shapes.
- Crypto-agnostic and account-agnostic interfaces. Use `validateAuth(digest, proof)`, not ERC-1271. The interface should not privilege any signature scheme or account type.
- Curve-specific data confined to `docs/appendix/pq-analysis.md`. Proposals stay scheme-agnostic so that adding ML-DSA today and MAYO-2 later doesn't require reopening the consensus spec.

### Binding and envelope discipline

- Use envelope fields only where consensus must bind pre-frame. Stream keys, validity bounds, yes. Inline PQ pubkeys, no (registry-only).
- Prefer contract storage over account encoding for new state.

### Alternative selection

- The five alternatives are presented neutrally. The repo doesn't pick.

---

## Status

These are research documents, not a submitted EIP. They are intended as:

1. Input to the ongoing EIP-8141 spec conversation.
2. A reference for wallet and application developers planning for rollout.

Pull requests, issues, and forked explorations are welcome.

# EIP-8141 Features

Feature proposals, primitive definitions, and per-alternative analysis layered on top of [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md) (Frame Transaction), the **native account-abstraction upgrade** for Ethereum.

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 lifts AA to the native protocol layer with a frame-based transaction model. The proposals in this repo expand the scope of that native AA upgrade. Each has been iterated against core dev and wallet dev review pressure.

---

## How to review this repo

1. Read `README.md` for scope and the repository map.
2. Read `docs/overview.md` for the alternative set and comparison table (technical, objective).
3. Read `docs/priorities.md` for the opinionated framing: which bundles are viable in one upgrade, what is load-bearing, what folds in (subjective companion to the overview).
4. Pick one alternative and read only its proposal doc.
5. Read the appendix files referenced by that proposal.

Terminology used across the docs is defined once in `docs/glossary.md`.

---

## TL;DR

The proposals expand the scope of the existing EIP-8141 upgrade. They ship in the same activation as EIP-8141, adding guarantors plus a chosen subset of three independent features:

- **flexible nonces**, protocol-native parallel nonce streams.
- **Signer binding**, registry-backed PQ identity for `ECRECOVER` callers.
- **Validity windows**, envelope-level `valid_after` / `valid_before` time bounds.

The proposals are presented as **five neutral alternatives**: three individual and two aggregated. No alternative is recommended; the choice is a tradeoff this repo does not take a position on.

| Alternative | Doc | Features bundled |
|---|---|---|
| flexible nonces | `docs/proposals/flexible-nonces.md` | flexible nonces |
| Signer binding | `docs/proposals/signer-binding.md` | Signer binding |
| Validity windows | `docs/proposals/validity-windows.md` | Validity windows |
| Key lanes | `docs/proposals/key-lanes.md` | flexible nonces + signer binding |
| Authorization scopes | `docs/proposals/authorization-scopes.md` | flexible nonces + signer binding + validity windows |

Every alternative ships guarantors (PR #11555) as the small mempool primitive that confirms the stream-advance invariant and unlocks public-mempool ERC-20 paymasters.

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
│   ├── flexible-nonces.md            # Individual: flexible nonces
│   ├── signer-binding.md       # Individual: registry-backed PQ identity
│   ├── validity-windows.md     # Individual: envelope time bounds
│   ├── key-lanes.md            # Aggregated: flexible nonces + signer binding
│   └── authorization-scopes.md # Aggregated: flexible nonces + signer binding + validity windows
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

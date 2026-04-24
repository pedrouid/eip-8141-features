# EIP-8141 Features

Feature proposals, primitive definitions, and recommended fork-scope analysis for [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md) (Frame Transaction) — the native account-abstraction proposal for Ethereum.

The work here originates from a research dive into how to extend EIP-8141 with additional primitives (2D nonces, validity windows, delegated permissions, guarantors) **without overwhelming core-dev review or breaking account encoding**. Each proposal has been iterated against core-dev and wallet-dev review pressure, then distilled into a recommended fork shape.

---

## TL;DR

Recommended shape for EIP-8141's first successful landing:

- **Base AA fork**: EIP-8141 + guarantors + 2D nonces + validity windows.
- **Follow-on v2 fork**: delegated permissions built on a standalone `execution-authority` EIP.

Net protocol surface of the base fork:

- **3 new envelope fields** (`nonce_key`, `valid_after`, `valid_before`).
- **1 new system contract** (`NonceLaneRegistry`, EIP-4788 pattern).
- **1 new APPROVE scope** (`APPROVE(guarantee)`).
- **2 new tx-scoped fields** (`guarantor`; and `execution_authority` when the standalone EIP ships).
- **Zero new opcodes.**
- **Zero new precompiles.**
- **Zero core-invariant changes.**
- **Zero account-encoding changes.**

Every piece has independent design precedent. Any one can be pulled from the fork without invalidating the others.

See [`docs/summary.md`](docs/summary.md) for the short pitch, [`docs/evaluation.md`](docs/evaluation.md) for the five-scenario analysis, and [`docs/plan.md`](docs/plan.md) for actionable proposal edits.

---

## Repository structure

```
docs/
├── summary.md               # Executive pitch for the recommended fork shape
├── evaluation.md            # Scenario analysis (A/B/C/D/E fork combinations)
├── plan.md                  # Sequencing, uncertainties, order of work
├── research.md              # 14-question deep dive with picks
│
├── 2d-nonces.md             # Feature: parallel nonce streams per account
├── validity-windows.md      # Feature: envelope-level time bounds on txs
├── permissions.md           # Feature: ERC-7710/7715-style delegated permissions (v2 fork)
│
├── guarantors.md            # Primitive: APPROVE(guarantee) and economic-risk mempool relaxation
├── execution-authority.md   # Primitive: tx-scoped execution authority for SENDER frames
└── sighash-binding.md       # Primitive: binding rules for protocol-visible frame data
```

---

## Design principles

Principles that every proposal in this repo follows. Deviations require explicit justification.

### Consensus-level minimalism

- No new opcodes.
- No new precompiles.
- No account-encoding changes — use the EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state.
- No core-invariant changes in the base fork. Changes to SENDER-frame `msg.sender` semantics, fundamental APPROVE rules, or nonce consumption belong in follow-on forks.

### First-class EIP-8141 primitives

- Don't inherit from contract-era ERCs. ERC-4337 makes compromises (192-bit key packing, bundler enforcement, `isValidSignature` naming) because it lives above the protocol. EIP-8141 has the freedom to choose better shapes.
- Crypto-agnostic and account-agnostic interfaces. Use `validateAuth(digest, proof)`, not ERC-1271. The interface should not privilege any signature scheme or account type.

### Binding and envelope discipline

- Use envelope fields only where consensus must bind pre-frame. Stream keys, validity bounds — yes. Delegation bundles (bound by an independent account-signed digest) — no.
- Prefer contract storage over account encoding for new state. System contracts at reserved addresses inherit existing machinery (snap sync, witnesses, state-tree transitions).

### Scope and sequencing

- Small v1 scopes with explicit v2 deferrals. See permissions' v1/v2 split for the canonical example.
- Core-dev feedback weighted higher than wallet-dev feedback. Core devs implement it and carry consensus risk; wallet devs can layer on top of what ships.
- Features that can land in contracts + wallet code instead of consensus should. See the ~85 % permissions-UX-via-contracts argument in `docs/evaluation.md`.

---

## Status

These are research documents, not a submitted EIP. They are intended as:

1. Input to the ongoing EIP-8141 spec conversation.
2. The basis for a companion EIP on the `execution-authority` primitive if the community path there proceeds.
3. A reference for wallet and application developers planning for the AA-fork rollout.

Pull requests, issues, and forked explorations are welcome.

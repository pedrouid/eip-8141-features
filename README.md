# EIP-8141 Upgrade

A proposal to expand the scope of [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md) (Frame Transaction), the **native account-abstraction upgrade** for Ethereum. Bundles guarantors, keyed nonce streams, signer binding, and an envelope `expiry` field into the same activation, on the basis that EIP-8141 is the one realistic opportunity to lift AA into the protocol layer.

Account abstraction already exists on Ethereum via ERC-4337 (above the protocol) and EIP-7702 (delegating to code). EIP-8141 lifts AA to the native protocol layer with a frame-based transaction model. This repo argues that the upgrade should land doing more than the minimum, since there will not be a second pass; the consolidated proposal has been iterated against core dev and wallet dev review pressure.

---

## How to review this repo

The canonical artifact is [`eip-8141.md`](eip-8141.md): the consolidated modified EIP draft, all four features folded in. [`docs/summary.md`](docs/summary.md) is the PR-body summary intended for upstream `ethereum/EIPs` submission. [`docs/compare.md`](docs/compare.md) is the delta map against upstream EIP-8141 and the related PRs. The reference contracts under [`assets/eip-8141/`](assets/eip-8141/) define the **canonical observable semantics** (entry points, ordering, errors, events); clients MAY implement equivalent native behavior outside EVM bytecode for performance, but whichever shape ships is code-hash pinned at activation. The six proposals under [`docs/proposals/`](docs/proposals/) are alternative scopes preserved for comparison; the consolidated draft executes the maximum bundle (Auth scopes). [`docs/appendix/test-matrix.md`](docs/appendix/test-matrix.md) lists conformance cases.

- **Core devs:** read [`eip-8141.md`](eip-8141.md), then [`docs/compare.md`](docs/compare.md), then the appendix specs referenced.
- **Wallet devs:** read this README, [`docs/priorities.md`](docs/priorities.md), and the wallet UX sections in proposals.
- **Infra devs:** read [`docs/appendix/mempool-tiers.md`](docs/appendix/mempool-tiers.md), [`docs/appendix/system-contracts.md`](docs/appendix/system-contracts.md), and the RPC sections.
- **App devs:** read the wallet UX and compatibility sections.

Terminology used across the docs is defined once in [`docs/glossary.md`](docs/glossary.md).

---

## TL;DR

The repo carries one consolidated proposal plus six alternative scopes preserved for comparison.

- **Consolidated proposal**, [`eip-8141.md`](eip-8141.md): the modified EIP draft. Adds guarantors, keyed nonce streams, signer binding, and an envelope `expiry` field. Single canonical authentication-state contract `AuthManager`. Reference contracts in [`assets/eip-8141/`](assets/eip-8141/). Delta map in [`docs/compare.md`](docs/compare.md).
- **Six alternative scopes** under [`docs/proposals/`](docs/proposals/): four individual features and two aggregated bundles, kept as the comparison surface. The consolidated proposal executes the Auth-scopes bundle, which folds in Envelope expiry (not Validity windows); the rationale is in [`docs/priorities.md`](docs/priorities.md).

Status legend:

- **Current EIP-8141:** external upstream spec. See [eip8141.io Current Spec](https://eip8141.io/current-spec), [Merged Changes](https://eip8141.io/merged-changes), and the [EIP text](https://eips.ethereum.org/EIPS/eip-8141).
- **Guarantors:** companion feature in flight as [PR #11555](https://github.com/ethereum/EIPs/pull/11555), folded into the consolidated proposal here.
- **Flexible nonces, signer binding, envelope expiry:** the three additions on top of guarantors. Validity windows is the two-sided sibling alternative to Envelope expiry; the consolidated draft ships Envelope expiry.

| Alternative | Doc | Features bundled | Registry shape |
|---|---|---|---|
| Flexible nonces | [`docs/proposals/flexible-nonces.md`](docs/proposals/flexible-nonces.md) | Flexible nonces | `NonceManager` |
| Signer binding | [`docs/proposals/signer-binding.md`](docs/proposals/signer-binding.md) | Signer binding | `PubkeyRegistry` |
| Validity windows | [`docs/proposals/validity-windows.md`](docs/proposals/validity-windows.md) | `valid_after` + `valid_before` | none |
| Envelope expiry | [`docs/proposals/envelope-expiry.md`](docs/proposals/envelope-expiry.md) | One-sided `expiry` | none |
| Key streams | [`docs/proposals/key-streams.md`](docs/proposals/key-streams.md) | Flexible nonces + signer binding | `AuthManager` (merged) |
| Auth scopes | [`docs/proposals/auth-scopes.md`](docs/proposals/auth-scopes.md) | Flexible nonces + signer binding + envelope expiry | `AuthManager` (merged) |

The consolidated [`eip-8141.md`](eip-8141.md) is the PR-shaped execution of Auth scopes.

Flexible nonces, Key streams, and Auth scopes are complementary to Guarantors: they reduce contention, isolate sponsorship flows, and bound authorization risk, which makes Guarantors more viable in public mempools.

See [`docs/overview.md`](docs/overview.md) for the per-alternative analysis and open uncertainties. See [`docs/priorities.md`](docs/priorities.md) for the load-bearing-weight argument that ranks the alternatives under the one-upgrade constraint.

---

## Repository structure

```
eip-8141.md                 # Consolidated modified EIP draft (executes Auth scopes)
eip-8141.diff               # Diff against upstream EIPS/eip-8141.md

assets/eip-8141/
├── AuthManager.sol         # Reference impl of the canonical authentication-state contract
├── AuthManager.sol.diff
├── CanonicalPaymaster.sol  # Reference impl with guarantor mode
└── CanonicalPaymaster.sol.diff

docs/
├── overview.md             # Per-alternative analysis and tradeoffs
├── priorities.md           # Load-bearing-weight argument; ranks bundles
├── compare.md              # Delta map for eip-8141.md vs upstream + related PRs
├── glossary.md             # Single canonical definition per term
├── summary.md              # PR-body summary for upstream ethereum/EIPs submission
│
├── proposals/              # Six alternative scopes; consolidated EIP executes Auth scopes
│   ├── flexible-nonces.md            # Individual: Flexible nonces (NonceManager)
│   ├── signer-binding.md             # Individual: registry-backed PQ identity (PubkeyRegistry)
│   ├── validity-windows.md           # Individual: two-sided validity bounds (valid_after + valid_before)
│   ├── envelope-expiry.md            # Individual: one-sided envelope deadline (expiry)
│   ├── key-streams.md                # Aggregated: Flexible nonces + signer binding (AuthManager)
│   └── auth-scopes.md                # Aggregated: all three with envelope expiry (AuthManager) -> eip-8141.md
│
└── appendix/               # Cross-cutting primitives, shared specs, and grounding analyses
    ├── guarantors.md           # Guarantor payer primitive, folded into the consolidated EIP
    ├── sighash-binding.md      # Class A/B binding analysis
    ├── system-contracts.md     # NonceManager, PubkeyRegistry, AuthManager: shared spec
    ├── verified-signers.md     # Verified-signers table + modified ECRECOVER: shared spec
    ├── mempool-tiers.md        # Restrictive / expansive / private tier semantics
    ├── pq-analysis.md          # NIST PQC + MAYO sizing; reth pipeline grounding
    └── test-matrix.md           # Conformance test cases for the consolidated EIP
```

---

## Design principles

Principles every proposal follows. Deviations require explicit justification.

### Consensus-level minimalism

- No new opcodes beyond the current EIP-8141 set (`APPROVE`, `TXPARAM`, `FRAMEDATALOAD`, `FRAMEDATACOPY`, `FRAMEPARAM`).
- No new precompiles.
- No account-encoding changes; use the EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state.
- No core-invariant changes. Changes to SENDER-frame `msg.sender` semantics, fundamental APPROVE rules, or nonce consumption are out of scope.

### First-class EIP-8141 primitives

- Don't inherit from contract-era ERCs. ERC-4337 makes compromises (192-bit key packing, bundler enforcement, `isValidSignature` naming) because it lives above the protocol. EIP-8141 has the freedom to choose better shapes.
- Crypto-agnostic and account-agnostic interfaces. Use `validateAuth(digest, proof)`, not ERC-1271. The interface should not privilege any signature scheme or account type.
- Curve-specific data confined to `docs/appendix/pq-analysis.md`. Proposals stay scheme-agnostic so that adding ML-DSA today and MAYO-2 later doesn't require reopening the consensus spec.

### Binding and envelope discipline

- Use envelope fields only where consensus must bind pre-frame. Stream keys and `expiry`, yes. Inline PQ pubkeys, no (registry-only).
- Prefer contract storage over account encoding for new state.

### Alternative selection

- The consolidated [`eip-8141.md`](eip-8141.md) executes the Auth-scopes bundle (all three features) under the one-upgrade constraint argued in [`docs/priorities.md`](docs/priorities.md). The five alternatives in [`docs/proposals/`](docs/proposals/) are preserved as the comparison surface.

---

## Status

These are research documents, not a submitted EIP. They are intended as:

1. Input to the ongoing EIP-8141 spec conversation.
2. A reference for wallet and application developers planning for rollout.

Pull requests, issues, and forked explorations are welcome.

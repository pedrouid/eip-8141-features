# EIP-8141 Features — Project Instructions

Instructions for AI agents and contributors working on this repository.

---

## Purpose

This repo contains feature proposals and analysis for [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md) (Frame Transaction), the native account-abstraction proposal for Ethereum. The goal is to identify the **minimal-scope AA fork that lands EIP-8141 successfully**, with a clear follow-on path for delegated permissions.

Every proposal is iterated against core-dev and wallet-dev review pressure, then distilled into a recommended fork shape.

---

## Current recommendation

**Base AA fork**: EIP-8141 + guarantors + 2D nonces + validity windows.
**Follow-on v2 fork**: delegated permissions built on a standalone `execution-authority` EIP.

See `docs/summary.md` and `docs/evaluation.md` for the full argument. `docs/plan.md` holds sequencing, remaining uncertainties, and order of work.

---

## Repository structure

All working docs live in `docs/`. Flat layout; filenames are self-describing.

| Category | Files |
|---|---|
| Feature proposals | `2d-nonces.md`, `validity-windows.md`, `permissions.md` |
| Protocol primitives | `execution-authority.md`, `guarantors.md`, `sighash-binding.md` |
| Decision docs | `research.md`, `plan.md`, `evaluation.md` |
| Executive pitch | `summary.md` |

**Feature proposals** describe user-facing capabilities with spec deltas.
**Primitives** describe protocol building blocks that features depend on.
**Decision docs** derive to concrete action items, in this order: `research.md` (14-question deep dive and picks) → `plan.md` (sequencing + uncertainties + order of work) → `evaluation.md` (fork-scope scenario analysis) → `summary.md` (executive pitch).

---

## Design principles

Principles every proposal follows. **Deviating requires explicit justification in the proposal itself.**

### Consensus-level minimalism

1. **No new opcodes.** Express new capability via existing EVM opcodes or protocol-level pre-frame checks.
2. **No new precompiles.** System contracts at reserved addresses are preferred when new state or logic is needed.
3. **No account-encoding changes.** The account RLP encoding (4-tuple: `nonce, balance, storageRoot, codeHash`) must not change. Use the EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state.
4. **No core-invariant changes in the base fork.** Changes to SENDER-frame `msg.sender` semantics, fundamental APPROVE rules, or nonce-consumption rules belong in follow-on forks.

### First-class EIP-8141 primitives

5. **Don't inherit from contract-era ERCs.** ERC-4337 makes compromises (192-bit key packing, bundler enforcement, `isValidSignature` naming) because it lives above the protocol. EIP-8141 has the freedom to choose better shapes; exercise it.
6. **Crypto-agnostic and account-agnostic interfaces.** Use `validateAuth(digest, proof)`, not ERC-1271. No field, parameter, or vocabulary should privilege any signature scheme or account type.

### Binding and envelope discipline

7. **Use envelope fields only where consensus must bind pre-frame.** Stream keys, validity bounds — yes. Delegation bundles (bound by an independent delegator-signed digest) — no.
8. **Prefer contract storage over account encoding for new state.** System contracts inherit existing machinery (snap sync, witnesses, state-tree transitions); new account fields do not.

### Scope and sequencing

9. **Small v1 scopes with explicit v2 deferrals.** See permissions' v1/v2 split for the canonical example.
10. **Core-dev feedback is weighted higher than wallet-dev feedback.** Core devs implement and carry consensus risk; wallet devs layer on top of what ships.
11. **Every feature that can land in contracts + wallet code instead of consensus should.** See the ~85 % permissions-UX-via-contracts argument in `docs/evaluation.md`.

---

## Writing style

- **No emojis.** Ever.
- **Em dashes are restricted.** Allowed only in (a) titles with subtitles, (b) dates attached to a label, (c) list/table topic-description separators. Never as parenthetical brackets, colon substitutes, or inside prose sentences. Rewrite with commas, periods, semicolons, colons, or parentheses.
- **Direct and terse.** No filler, no trailing summaries.
- **No individual author attribution on scratch docs.** The scratch-doc header is the source identifier; individual contributors aren't named.
- **Feature proposals follow**: Priorities → Single-line spec delta → Envelope/state changes → Consensus rules → Mempool rules → RPC → Wallet UX → Interactions with other primitives → Comparison → Non-goals → Spec delta summary.
- **Primitive docs follow**: Problem → Design → Invariants → Implications → Spec delta.

### Scratch-doc header

Every doc opens with:

```
# <Title>

_Scratch doc, not indexed on the site._
```

Optionally extend with one sentence of context (e.g., "Prerequisite for the permissions proposal.") if useful. No author attribution.

This marks docs as iterative research output, not a publishable spec. When a doc is upstreamed to the actual EIP or an EIPs-repo PR, the scratch-doc header is removed and the content is restructured for the target format.

---

## Word-count targets

| Doc type | Target |
|---|---|
| `summary.md` | ≤ 300 words |
| Feature proposals, primitive docs | ≤ 1 000 words |
| `plan.md`, `research.md`, `evaluation.md` | ≤ 2 000 words |

Keep proposals lean. If a doc exceeds its target, compress before adding new content.

---

## When picking up work

1. Read `docs/summary.md` first for the current recommendation.
2. Read `docs/evaluation.md` for why the recommendation is what it is.
3. Read `docs/plan.md` for sequencing and the order of work.
4. Read `docs/research.md` for the 14 open questions and their resolutions.
5. If working on a specific proposal, read it directly; feedback pressure is already baked in.

---

## When changing the recommendation

If an argument surfaces that changes the recommended fork shape, update in this order:

1. The relevant feature proposal or primitive doc.
2. `docs/plan.md` if sequencing or uncertainties change.
3. `docs/evaluation.md` scenario analysis.
4. `docs/summary.md` top-line pitch.
5. `README.md` TL;DR.

Keep the chain of reasoning visible.

---

## When closing out a research cycle

Before committing:

- Run a consistency pass: grep for stale references (e.g., `lanesRoot` was replaced by `NonceLaneRegistry` — any lingering mention is a bug).
- Verify that `research.md` picks, `plan.md` sequencing, and the proposals agree.
- Check that the scratch-doc header is present on every file and no author attributions leaked in.
- Check no em-dash violations.
- Check word-count targets.

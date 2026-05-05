# EIP-8141 Upgrade, Project Instructions

Instructions for AI agents and contributors working on this repository.

---

## Purpose

This repo proposes an **expansion of [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md)** (Frame Transaction), the **native AA upgrade** for Ethereum. AA already exists via ERC-4337 and EIP-7702; EIP-8141 lifts AA to the native protocol layer. The proposals here extend that upgrade's scope. Each proposal is iterated against core dev and wallet dev review pressure.

**`docs/overview.md` does not pick a recommended alternative.** Five neutral alternatives are presented for core devs and wallet devs to weigh. The subjective companion is `docs/priorities.md`, which ranks the alternatives by load-bearing weight under the one-upgrade constraint and rules out standalone Flexible nonces and Validity windows on that basis. The two docs are paired: overview is technical and objective, priorities is product-y and subjective.

---

## Expanded native AA upgrade

EIP-8141 + guarantors + a chosen subset of three independent features:

- **Flexible nonces**
- **Signer binding** (registry-only; inline-envelope path explicitly rejected)
- **Validity windows**

Five alternatives (three individual + two aggregated):

| Alternative | Doc | Features |
|---|---|---|
| Flexible nonces | `docs/proposals/flexible-nonces.md` | Flexible nonces |
| Signer binding | `docs/proposals/signer-binding.md` | Signer binding |
| Validity windows | `docs/proposals/validity-windows.md` | Validity windows |
| Key lanes | `docs/proposals/key-lanes.md` | Flexible nonces + signer binding |
| Authorization scopes | `docs/proposals/authorization-scopes.md` | Flexible nonces + signer binding + validity windows |

---

## Repository structure

Directory-based layout. All proposal docs live under `docs/proposals/`.

```
docs/
├── overview.md             # Read first; covers scope, the five alternatives, and tradeoffs
├── priorities.md           # Subjective companion; ranks bundles under the one-upgrade constraint
├── glossary.md             # Single canonical definition per term
│
├── proposals/              # Pick one alternative
│   ├── flexible-nonces.md
│   ├── signer-binding.md
│   ├── validity-windows.md
│   ├── key-lanes.md            # Aggregated (Flexible nonces + signer binding)
│   └── authorization-scopes.md # Aggregated (all three)
│
└── appendix/               # Cross-cutting primitives, shared specs, and grounding analyses
    ├── guarantors.md           # In every alternative
    ├── sighash-binding.md      # Class A/B binding analysis
    ├── system-contracts.md     # NonceLaneRegistry + PubkeyRegistry: shared spec
    ├── verified-signers.md     # Verified-signers table + modified ECRECOVER: shared spec
    ├── mempool-tiers.md        # Restrictive / expansive / private tier semantics
    └── pq-analysis.md          # NIST PQC + MAYO sizing; reth pipeline grounding
```

**Feature proposals** describe user-facing capabilities with spec deltas. Proposals reference the shared appendix specs rather than duplicating them.
**Appendix** holds cross-cutting primitives, shared specs (system contracts, verified-signers table + modified ECRECOVER, mempool tiers), and grounding analyses (PQ sizing, reth pipeline). PQ-analysis absorbs scheme-specific detail so proposals stay scheme-agnostic.
**Top-level docs** are `overview.md` (technical: per-alternative analysis, comparison table, open uncertainties) and `priorities.md` (subjective: ranks the alternatives by load-bearing weight, argues the one-upgrade constraint, names viable bundles).

---

## Design principles

Principles every proposal follows. **Deviating requires explicit justification in the proposal itself.**

### Consensus-level minimalism

1. **No new opcodes.** Express new capability via existing EVM opcodes or protocol-level pre-frame checks.
2. **No new precompiles.** System contracts at reserved addresses are preferred when new state or logic is needed.
3. **No account-encoding changes.** The account RLP encoding (4-tuple: `nonce, balance, storageRoot, codeHash`) must not change. Use the EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state.
4. **No core-invariant changes.** Changes to SENDER-frame `msg.sender` semantics, fundamental APPROVE rules, or nonce-consumption rules are out of scope.

### First-class EIP-8141 primitives

5. **Don't inherit from contract-era ERCs.** ERC-4337 makes compromises (192-bit key packing, bundler enforcement, `isValidSignature` naming) because it lives above the protocol. EIP-8141 has the freedom to choose better shapes; exercise it.
6. **Crypto-agnostic and account-agnostic interfaces.** Use `validateAuth(digest, proof)`, not ERC-1271. No field, parameter, or vocabulary should privilege any signature scheme or account type.
7. **Curve-specific data confined to `docs/appendix/pq-analysis.md`.** Proposals stay scheme-agnostic. Concrete scheme parameters (ML-DSA, Falcon, SLH-DSA, MAYO) live in the background doc and the `signature_type` registry; not in the proposals.

### Binding and envelope discipline

8. **Use envelope fields only where consensus must bind pre-frame.** Stream keys, validity bounds, yes. Inline PQ pubkeys, no (registry-only).
9. **Prefer contract storage over account encoding for new state.** System contracts inherit existing machinery (snap sync, witnesses, state-tree transitions); new account fields do not.

### Scope and isolation

10. **Core-dev feedback is weighted higher than wallet-dev feedback.** Core devs implement and carry consensus risk; wallet devs layer on top of what ships.
11. **Every feature that can land in contracts + wallet code instead of consensus should.**

### Signer binding is registry-only

The `signer-binding.md` proposal (and any aggregated alternative including it) uses the `PubkeyRegistry` system contract as the single source of pubkeys. Inlining pubkeys in the tx envelope is explicitly rejected. The size case is exclusive to lattice (897 B-2.6 KB) and multivariate (1.2-5.5 KB) schemes; hash-based pubkeys (SLH-DSA: 32-64 B) are size-compatible with inlining but registry is still the right call to avoid forking the protocol into two pubkey-resolution paths. The recovery problem (no PQ scheme admits recovery) is what makes a pubkey lookup unavoidable in the first place; registry-vs-envelope is the choice of *how* to expose that lookup. See `docs/appendix/pq-analysis.md`.

---

## Writing style

- **No emojis.** Ever.
- **Em dashes are restricted.** Allowed only in (a) titles with subtitles, (b) dates attached to a label, (c) list/table topic-description separators. Never as parenthetical brackets, colon substitutes, or inside prose sentences. Rewrite with commas, periods, semicolons, colons, or parentheses.
- **Direct and terse.** No filler, no trailing summaries.
- **No individual author attribution on scratch docs.**
- **Feature proposals follow**: Priorities → Single-line spec delta → Envelope/state changes → Consensus rules → Mempool rules → RPC → Wallet UX → Interactions with other primitives → Comparison → Non-goals → Spec delta summary.
- **Primitive docs follow**: Problem → Design → Invariants → Implications → Spec delta.

### Cross-cutting additions every proposal should include

- **Mempool-tier classification**, short table or paragraph naming which flows land in restrictive vs. expansive vs. private tiers.
- **PQ-compatibility note**, one paragraph pointing at `docs/appendix/pq-analysis.md` for scheme-specific data.
- **FOCIL-compatibility note**, one paragraph citing attester-facing invariants relevant to the proposal.
- **Stream-advance-on-inclusion rule**, for any proposal including Flexible nonces, pin the normative invariant that the per-stream sequence advances on successful inclusion regardless of VERIFY outcome. Cited from `docs/appendix/guarantors.md`.

### Doc header

Every doc opens with `# <Title>`, optionally followed by a single italicised context line that names the doc's role (e.g., `_Individual alternative._`, `_Cross-cutting binding analysis._`). No author attribution. No scratch-doc disclaimer.

---

## Word-count targets

**Every doc has a hard limit of 1400 words, no exceptions.** This applies to overview, proposals (individual and aggregated), primitives, shared specs, and background analyses alike. If a doc would exceed 1400, compress or extract shared content into a new appendix doc before adding new material.

---

## When picking up work

1. Read `docs/overview.md` first; it covers the per-alternative analysis and open uncertainties.
2. Read `docs/priorities.md` for the opinionated framing: which bundles are viable in one upgrade, what is load-bearing, what folds in, what falls out.
3. If working on a specific proposal, read it directly; feedback pressure is already baked in.
4. Shared specs live in `docs/appendix/`: registry contracts (`system-contracts.md`), verified-signers table + modified ECRECOVER (`verified-signers.md`), mempool tiers (`mempool-tiers.md`), curve data (`pq-analysis.md`). Proposals reference these; don't duplicate them.

---

## When picking an alternative

If an alternative is selected, update in this order to keep the chain of reasoning visible:

1. The relevant proposal doc (already aligned via the per-alternative content).
2. `docs/overview.md` if the per-alternative analysis, comparison table, or open-uncertainties section needs to move.
3. `docs/priorities.md` if the ranking or the viable-bundles list shifts.
4. `README.md` TL;DR.

The current state of the repo assumes no alternative has been picked.

---

## When closing out a research cycle

Before committing:

- Run a consistency pass: grep for stale references (e.g., `lanesRoot` was replaced by `NonceLaneRegistry`, any lingering mention is a bug; envelope `pubkeys` field was removed, any lingering mention is a bug).
- Verify that `overview.md` open-uncertainties and the proposals agree.
- Verify no curve-specific names (ML-DSA, Falcon, SLH-DSA, SPHINCS+, MAYO, Dilithium) appear in proposals; those belong in `pq-analysis.md`.
- Check that no author attributions leaked in and that no doc reintroduces the old scratch-doc disclaimer line in its header.
- Check no em-dash violations.
- Check word-count targets.

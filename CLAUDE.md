# EIP-8141 Upgrade, Project Instructions

Instructions for AI agents and contributors working on this repository.

---

## Purpose

This repo proposes an **expansion of [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md)** (Frame Transaction), the **native AA upgrade** for Ethereum. AA already exists via ERC-4337 and EIP-7702; EIP-8141 lifts AA to the native protocol layer. The repo carries one consolidated proposal and five alternative scopes preserved for comparison. Each is iterated against core dev and wallet dev review pressure.

**Canonical artifact:** `eip-8141.md` is the consolidated modified EIP draft, executing the Auth-scopes bundle (guarantors + flexible nonces + signer binding + envelope expiry) under a single `AuthManager` system contract. `docs/compare.md` is the delta map vs upstream and related PRs. `docs/summary.md` is the PR-body summary used when submitting upstream to `ethereum/EIPs`; keep it in sync whenever the consolidated bundle changes.

**Alternatives** under `docs/proposals/` are kept as the comparison surface and as compromise paths if scope shrinks. `docs/overview.md` enumerates them; `docs/priorities.md` argues the load-bearing-weight ranking, ruling out standalone Flexible nonces, Validity windows, and Envelope expiry, and arguing Envelope expiry over Validity windows on cost-per-envelope-byte grounds.

---

## Expanded native AA upgrade

EIP-8141 + guarantors + three independent features:

- **Flexible nonces**
- **Signer binding** (registry-only; inline-envelope path explicitly rejected)
- **Envelope expiry** (one-sided deadline; preferred over the two-sided Validity windows alternative on cost-per-envelope-byte grounds)

Six alternatives (four individual + two aggregated). Validity windows and Envelope expiry are mutually exclusive standalones; Auth scopes folds in Envelope expiry.

| Alternative | Doc | Features | Registry |
|---|---|---|---|
| Flexible nonces | `docs/proposals/flexible-nonces.md` | Flexible nonces | `NonceManager` |
| Signer binding | `docs/proposals/signer-binding.md` | Signer binding | `PubkeyRegistry` |
| Validity windows | `docs/proposals/validity-windows.md` | `valid_after` + `valid_before` | none |
| Envelope expiry | `docs/proposals/envelope-expiry.md` | One-sided `expiry` | none |
| Key streams | `docs/proposals/key-streams.md` | Flexible nonces + signer binding | `AuthManager` (merged) |
| Auth scopes | `docs/proposals/auth-scopes.md` | Flexible nonces + signer binding + envelope expiry | `AuthManager` (merged) |

The consolidated `eip-8141.md` ships Auth scopes. `AuthManager` is the canonical authentication-state contract carrying both keyed nonce streams and signer registrations under one address, and is what makes a single-contract identity surface possible across any signature scheme (secp256k1, lattice, multivariate, hash-based).

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
├── compare.md              # Delta map for eip-8141.md vs upstream and related PRs
├── glossary.md             # Single canonical definition per term
├── summary.md              # PR-body summary for upstream ethereum/EIPs submission
│
├── proposals/              # Six alternative scopes; consolidated EIP executes Auth scopes
│   ├── flexible-nonces.md
│   ├── signer-binding.md
│   ├── validity-windows.md       # Two-sided (valid_after + valid_before)
│   ├── envelope-expiry.md        # One-sided (expiry); folded into Auth scopes
│   ├── key-streams.md            # Aggregated (Flexible nonces + signer binding)
│   └── auth-scopes.md            # Aggregated (all three, with envelope expiry) -> eip-8141.md
│
└── appendix/               # Cross-cutting primitives, shared specs, and grounding analyses
    ├── guarantors.md           # Folded into the consolidated EIP
    ├── sighash-binding.md      # Class A/B binding analysis
    ├── system-contracts.md     # NonceManager, PubkeyRegistry, AuthManager: shared spec
    ├── verified-signers.md     # Verified-signers table + modified ECRECOVER: shared spec
    ├── mempool-tiers.md        # Restrictive / expansive / private tier semantics
    ├── pq-analysis.md          # NIST PQC + MAYO sizing; reth pipeline grounding
    └── test-matrix.md           # Conformance test cases for the consolidated EIP
```

**Feature proposals** describe user-facing capabilities with spec deltas, referencing shared appendix specs rather than duplicating them.
**Appendix** holds cross-cutting primitives, shared specs (system contracts, verified-signers table, mempool tiers), and grounding analyses (PQ sizing, reth pipeline). PQ-analysis absorbs scheme-specific detail so proposals stay scheme-agnostic.
**Top-level docs** are `eip-8141.md` (consolidated PR-shaped draft), `docs/compare.md` (delta map), `docs/overview.md` (per-alternative analysis), and `docs/priorities.md` (load-bearing-weight ranking).

---

## Design principles

Principles every proposal follows. **Deviating requires explicit justification in the proposal itself.**

### Consensus-level minimalism

1. **No new opcodes beyond the current EIP-8141 set.** Express new capability via existing opcodes or protocol-level pre-frame checks.
2. **No new precompiles.** System contracts at reserved addresses are preferred when new state or logic is needed.
3. **No account-encoding changes.** The account RLP encoding (4-tuple: `nonce, balance, storageRoot, codeHash`) must not change. Use the EIP-4788 / EIP-2935 system-contract pattern for new protocol-visible state.
4. **No core-invariant changes.** Changes to SENDER-frame `msg.sender` semantics, fundamental APPROVE rules, or nonce-consumption rules are out of scope.

### First-class EIP-8141 primitives

5. **Don't inherit from contract-era ERCs.** ERC-4337 makes compromises (192-bit key packing, bundler enforcement, `isValidSignature` naming) because it lives above the protocol. EIP-8141 has the freedom to choose better shapes; exercise it.
6. **Crypto-agnostic and account-agnostic interfaces.** Use `validateAuth(digest, proof)`, not ERC-1271. No field, parameter, or vocabulary should privilege any signature scheme or account type.
7. **Curve-specific data confined to `docs/appendix/pq-analysis.md`.** Proposals stay scheme-agnostic in their *spec text* (envelope fields, mempool rules, consensus checks, interface signatures): no field, parameter, or vocabulary should privilege any signature scheme. Concrete scheme parameters (pubkey sizes, signature sizes, verify costs) live in `pq-analysis.md` and the `signature_type` registry. **Citing cryptographic curve / scheme names by name is fine anywhere** (secp256k1, ML-DSA, Falcon, SLH-DSA, MAYO, SPHINCS+, Dilithium, etc.): they are cryptographic primitives, not project / vendor names, and naming them in motivation, rationale, or load-bearing arguments is allowed and often necessary.

### Binding and envelope discipline

8. **Use envelope fields only where consensus must bind pre-frame.** Stream keys and `expiry`, yes. Inline PQ pubkeys, no (registry-only).
9. **Prefer contract storage over account encoding for new state.** System contracts inherit existing machinery (snap sync, witnesses, state-tree transitions); new account fields do not.

### Scope and isolation

10. **Core-dev feedback is weighted higher than wallet-dev feedback.** Core devs implement and carry consensus risk; wallet devs layer on top of what ships.
11. **Every feature that can land in contracts + wallet code instead of consensus should.**

### Signer binding is registry-only

Signer binding uses a canonical signer registry (`PubkeyRegistry` standalone, `AuthManager` aggregated) as the single source of pubkeys. Inline envelope pubkeys are rejected. Recovery is unavailable for any PQ scheme, so a lookup is unavoidable. Lattice (897 B-2.6 KB) and multivariate (1.2-5.5 KB) make inlining impractical on size; for hash-based the case is uniform interface, not size. See `docs/appendix/pq-analysis.md`.

---

## Writing style

- **No emojis.**
- **Em dashes restricted.** Allowed only in titles with subtitles, labelled dates, or list/table topic separators. Never as parentheticals, colon substitutes, or in prose. Rewrite with commas, periods, semicolons, colons, or parentheses. **Exception: upstream verbatim.** Em dashes inside text copied verbatim from upstream EIP-8141 are preserved unconditionally; the verbatim-preservation rule supersedes the em-dash rule.
- **Avoid `base` terminology.** Use "current EIP-8141", "current spec", "upstream spec", "existing rule", or "shared context".
- **Direct and terse.** No filler, no trailing summaries.
- **No author attribution.** No scratch-doc disclaimer.
- **Feature proposals follow**: Priorities → Single-line spec delta → Envelope/state → Consensus rules → Mempool → RPC → Wallet UX → Interactions → Comparison → Non-goals → Spec delta summary.
- **Primitive docs follow**: Problem → Design → Invariants → Implications → Spec delta.
- Every doc opens with `# <Title>`, optionally followed by one italicised context line (e.g., `_Individual alternative._`).

### Cross-cutting additions every proposal includes

- Mempool-tier classification (restrictive / expansive / private).
- PQ-compatibility note pointing at `docs/appendix/pq-analysis.md`.
- FOCIL-compatibility note.
- For Flexible-nonces proposals: stream-advance-on-inclusion rule from `docs/appendix/guarantors.md`.

---

## Word-count targets

**`eip-8141.md` is exempt from the 1400-word rule.** It is the consolidated EIP draft; word count is never a reason to trim or compress it. Every other doc has a hard limit of 1400 words; if one would exceed it, compress or extract shared content into a new appendix doc before adding new material.

`eip-8141.md` MUST preserve upstream EIP-8141 verbatim except where additions specifically change it. Never rewrite or compress upstream text.

---

## CI lint rules for `eip-8141.md`

Upstream `ethereum/EIPs` runs two checks on `EIPS/eip-8141.md` on every PR push. The same constraints apply to our `eip-8141.md` because we copy it verbatim into the PR branch. Violations block PR #11643.

### eipw (EIP Walidator)

- **`markdown-no-backticks`**: no inline-code span (`` `...` ``) may contain a substring matching `(?i)(eip|erc)-[0-9]+`. This includes filepath references that contain `eip-8141` (e.g. `assets/eip-8141/AuthManager.sol`). Use plain text or link syntax instead.
- **`markdown-refs`**: any prose token matching `(?i)(eip|erc)-[0-9]+` is parsed as a proposal reference and must use the canonical-case prefix for that proposal's `category:`. **Core**-track EIPs use `EIP-`; **ERC**-track proposals use `ERC-`. This applies to visible markdown text including **link text**, but NOT to URLs. So `[AuthManager reference contract](./assets/eip-8141/AuthManager.sol)` is fine (URL contains lowercase `eip-8141`, but link text doesn't), whereas `[assets/eip-8141/AuthManager.sol](./assets/eip-8141/AuthManager.sol)` fails (link text contains lowercase `eip-8141`, EIP-8141 is Core, must be `EIP-`). **Rule of thumb**: when linking into `./assets/eip-8141/...`, use a descriptive link text that does NOT contain the `eip-8141` substring (e.g. `[AuthManager reference contract]`, `[canonical paymaster reference contract]`, `[the AuthManager.sol asset]`).
- **Known correct prefixes for proposals we reference**:
  - Core (use `EIP-`): EIP-1559, EIP-2718, EIP-2929, EIP-2935, EIP-3607, EIP-4788, EIP-4844, EIP-7623, EIP-7702, EIP-7819, EIP-7997, EIP-8141.
  - ERC (use `ERC-`): ERC-20, ERC-165, ERC-721, ERC-1155, ERC-1271, ERC-2612, ERC-4337, ERC-7562.
  - When in doubt, check the `category:` field of the target proposal's front matter.

### markdownlint

- **`MD031/blanks-around-fences`**: every fenced code block (`` ``` ``) needs a blank line above and a blank line below, including when the fence is indented inside an ordered or unordered list. The list-item text continuation must also be separated from the closing fence by a blank line.

These rules apply only to `eip-8141.md` (the upstream-shaped draft). Other docs in `docs/` are not validated by upstream CI, so the rules are advisory there; still follow them for consistency.

---

## When picking up work

1. Read `eip-8141.md` and `docs/compare.md` first; they describe the consolidated proposal and what it changes vs upstream.
2. Read `docs/overview.md` for the per-alternative analysis and open uncertainties; `docs/priorities.md` for the load-bearing-weight ranking under the one-upgrade constraint.
3. Check [eip8141.io Current Spec](https://eip8141.io/current-spec), [Merged Changes](https://eip8141.io/merged-changes), and active related PRs before changing status-sensitive text.
4. If working on a specific proposal, read it directly; feedback pressure is already baked in.
5. Shared specs live in `docs/appendix/`: registry contracts (`system-contracts.md`), verified-signers table + modified ECRECOVER (`verified-signers.md`), mempool tiers (`mempool-tiers.md`), curve data (`pq-analysis.md`). Proposals reference these; don't duplicate them.
6. Reference contract impls live in `assets/eip-8141/`: `AuthManager.sol`, `CanonicalPaymaster.sol`, plus their `.diff` counterparts against upstream. Update them when consensus-relevant behaviour changes.

---

## When changing scope

If the consolidated bundle changes (e.g., a feature drops to a smaller alternative), update in this order:

1. `eip-8141.md` and the corresponding `assets/eip-8141/*.sol`.
2. `docs/compare.md` to keep the delta map honest.
3. Relevant proposal doc(s) under `docs/proposals/`.
4. `docs/overview.md` if analysis, comparison table, or open uncertainties move.
5. `docs/priorities.md` if the ranking shifts.
6. `docs/summary.md` so the upstream PR-body stays accurate.
7. `README.md` TL;DR.

## When closing out a research cycle

- Consistency pass: grep for stale references. Examples: stale `lanesRoot`; stale envelope `pubkeys` field; aggregated proposals + consolidated EIP must use `AuthManager`; standalone Flexible-nonces uses `NonceManager` and standalone Signer-binding uses `PubkeyRegistry`.
- Verify `overview.md`, proposals, `compare.md`, and `eip-8141.md` agree on names, fields, and constants.
- Curve / scheme parameter *data* (pubkey sizes, signature sizes, verify costs) belongs in `pq-analysis.md`. Citing curve / scheme *names* (ML-DSA, Falcon, SLH-DSA, SPHINCS+, MAYO, Dilithium, secp256k1) in proposals, rationale, or arguments is fine: they are cryptographic primitives, not project names.
- No author attributions, no scratch-doc disclaimer.
- No em-dashes, except inside text copied verbatim from upstream EIP-8141 (upstream verbatim is preserved unconditionally). Word-count targets met for every doc except `eip-8141.md` (exempt).

# EIP-8141 Upgrade, Project Instructions

## Purpose

This repo carries a rebased expansion of current EIP-8141. Preserve outcomes, not obsolete mechanisms.

Canonical bundle:

- native ordered nonce-key sets and protocol-managed replay domains;
- native nonceless mode with bounded consensus replay state;
- guarantors for public relay of arbitrary sender validation;
- transaction-scoped signer binding for existing `ECRECOVER` callers.

Research surfaces:

- use EIP-8250 as design provenance, not as the owner of keyed nonce semantics;
- use EIP-8164 as design provenance for alternative-key authentication and transaction-scoped signer binding;
- benchmark the coupled L1 expiry-window and replay-buffer-capacity activation values;
- use the upstream expiry verifier instead of envelope deadlines.

The canonical draft is `EIPS/eip-8141.md`. It must preserve current upstream text verbatim except where the four additions require a change. `docs/compare.md` is the migration/delta map. `docs/summary.md` is the upstream PR body.

## Current architecture

Current upstream EIP-8141 already has:

- `signatures = [[scheme, signer, msg, signature], ...]`;
- secp256k1, P256, and `ARBITRARY` signature entries;
- `SIGPARAM` and `SIGDATACOPY`;
- explicit `limits = [execution, state]`;
- current receipt, gas, atomic-batch, expiry, blob, and mempool rules.

Do not restore:

- the local `uint64 signer` envelope field;
- `AuthManager` or a mandatory pubkey registry;
- `compute_frame_sig_hash`;
- envelope expiry;
- one-dimensional `frame.gas_limit` terminology.

## Repository structure

```text
EIPS/
  eip-8141.md
  eip-8141.diff

assets/eip-8141/
  CanonicalPaymaster.sol
  CanonicalPaymaster.sol.diff

docs/
  overview.md
  priorities.md
  compare.md
  summary.md
  glossary.md
  article.md
  proposals/
    flexible-nonces.md
    signer-binding.md
    key-streams.md
    nonceless-transactions.md
    auth-scopes.md
    envelope-expiry.md
    validity-windows.md
  appendix/
    guarantors.md
    verified-signers.md
    system-contracts.md
    sighash-binding.md
    mempool-tiers.md
    pq-analysis.md
    test-matrix.md
```

## Design principles

1. Rebase from current `ethereum/EIPs` master before changing the canonical draft.
2. No new opcodes, precompiles, or account-RLP fields.
3. Reuse current signature-list and frame-introspection surfaces.
4. Account code is the signer-binding authority.
5. EIP-8141 remains authoritative for keyed nonce sets; EIP-8250 is design provenance.
6. Guarantor replay after failed sender validation stays in the canonical paymaster, not the sender's selected nonce set.
7. Deadlines use the expiry verifier frame.
8. Nonceless replay state is native to EIP-8141; concrete L1 expiry and capacity values remain a Draft activation gate.
9. Core-dev feedback and implementability outweigh speculative UX breadth.

## Canonical flag layout

- bits 0 through 2: approval scope;
- `APPROVE_GUARANTEE = 0x04`;
- bit 3: `ATOMIC_BATCH_FLAG = 0x08`;
- bit 4: `SIGNER_BINDING_FLAG = 0x10`.

`FRAMEPARAM(0x0C)` returns actual approved scope for a completed frame.

## Guarantor invariants

- A guarantee sets payer/guarantor but does not immediately consume sender replay state.
- Only the structurally identified `APPROVE_EXECUTION` sender-validation frame may fail after a guarantee.
- Failed sender validation skips later `SENDER` frames.
- Canonical paymaster authenticates the full canonical hash through a protocol-validated signature entry.
- The required settlement frame has flags exactly `APPROVE_PAYMENT`, at least `40,000` execution gas, and enough state gas for selected sequenced or nonceless replay consumption or the guarantor fallback nonce.
- On sender success the settlement frame consumes the selected replay protection while retaining the guarantor's escrow; on failure it advances `guarantor_nonce`.

## Nonceless invariants

- `[NONCE_KEY_MAX]` is a native EIP-8141 singleton mode with sequence zero.
- The canonical expiry verifier is first and its deadline is within the consensus expiry window.
- Replay identity excludes fees, frame gas limits, and raw signature bytes, but commits to logical execution and authorization metadata.
- Live-map and current-ring checks occur before frame execution.
- Replay insertion occurs only during sender-authorized payment approval and can create at most four slots (`391,680` state gas).
- `NONCELESS_EXPIRY_WINDOW` and `REPLAY_BUFFER_CAPACITY` remain coupled Draft activation parameters pending L1 benchmarks.

## Signer-binding invariants

- Binding frame flags equal `SIGNER_BINDING_FLAG` exactly.
- Mode is `VERIFY`; target is explicit; approval scope is zero.
- Return data is a non-empty concatenation of 32-byte digests.
- Duplicate same pair is a no-op; conflicting address reverts.
- Maximum eight unique digests per transaction.
- `ECRECOVER` miss behavior remains unchanged.
- Binding failure is never covered by the guarantor exception.

## Writing style

- No emojis.
- Direct and terse.
- Use current EIP terminology exactly.
- Do not call current upstream the "base" spec.
- Preserve upstream prose verbatim when rebasing.
- Every non-EIP doc must remain at or below 1,400 words.

## Upstream lint constraints

For `EIPS/eip-8141.md`:

- asset links resolve from `EIPS/` as `../assets/eip-8141/...`;
- inline-code spans must not contain a lowercase proposal reference such as `eip-8141`;
- use canonical proposal prefixes (`EIP-` for Core, `ERC-` for ERC);
- fenced code blocks need blank lines before and after;
- preserve valid front matter and relative links.

## Rebase workflow

1. Record clean/dirty state, branch, remotes, and upstream commit.
2. Fetch current EIP-8141, EIP-8250, EIP-8130, and canonical paymaster.
3. Start `EIPS/eip-8141.md` and the paymaster asset from current upstream.
4. Reapply keyed-nonce, nonceless, guarantor, and signer-binding deltas semantically.
5. Regenerate both `.diff` files against the same upstream commit.
6. Update compare, summary, overview, priorities, glossary, proposals, appendices, README, and this file.
7. Search for removed terminology and old opcode/flag/gas layouts.
8. Run link, word-count, whitespace, Solidity, and EIP validation available locally.

## Consistency checks

Search for stale:

- `AuthManager`, `AUTH_MANAGER`, registry-required binding;
- `tx.signer`, one `signer` envelope field;
- `compute_frame_sig_hash` or frame-elide hash;
- atomic flag `0x04`;
- one-dimensional `frame.gas_limit`;
- `TXPARAM(0x0B)` described as a hash;
- guarantor consumption of the sender's selected nonce set after failed validation;
- nonceless replay keyed by full transaction hash.

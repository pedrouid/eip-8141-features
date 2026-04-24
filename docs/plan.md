# Plan — Sequencing and Remaining Work

_Scratch doc, not indexed on the site. Decisions and derivations live in `research.md`; scenario analysis in `evaluation.md`; the recommendation in `summary.md`. This doc is the action plan after those decisions are applied to the proposals._

## Sequencing

**Validity windows → 2D nonces → Permissions.**

- **Validity windows** ship in the same fork as base EIP-8141 if possible. Minimal blast radius, maximum user-safety upside.
- **2D nonces** ship once state encoding + VOPS treatment are settled. Do not block validity windows on 2D-nonce state design.
- **Permissions** become a follow-on EIP depending on a standalone `execution-authority` EIP. Do not bundle with base 8141.

Matches both reviews: validity windows first, 2D nonces second (needs state design), permissions third (narrow v1 or its own EIP).

## Remaining uncertainties

Two picks flagged as "best-guess pending data"; neither blocks proposal edits.

| # | Question | Reason still open |
| - | --- | --- |
| 6 | VOPS state-growth budget | Back-of-envelope math; needs cross-client benchmarks. Registry-contract design makes this measurable (per-slot pressure). |
| 12 | Size caps (proof / caveat / bundle) | PQ signature landscape still evolving; 8 KB proof is right for ML-DSA, under-spec for large SPHINCS+. |

Q7 (`LANE_ALLOCATION_COST`) was previously flagged; now resolved by construction — first-use collapses into SSTORE-from-zero (20 000 gas) inside the registry.

## Order of work

1. **Validity windows**: close to ready-to-submit as a standalone EIP.
2. **`execution-authority` EIP**: extract as a standalone EIP (per Q9). Small, self-contained, unblocks permissions.
3. **Guarantor primitive alignment**: converge with PR #11555. Primitive lands in-fork; manager-as-guarantor deferred to permissions v2 (per Q10).
4. **2D nonces state appendix**: use the `NonceLaneRegistry` system-contract design (EIP-4788 pattern, no account-encoding change).
5. **2D nonces VOPS + FOCIL + RPC surface expansion**.
6. **Permissions v1 narrowing**: canonical caveat vocabulary, fork-scope inclusion, post-op semantics, revocation interface, PQ-migration appendix, manager-as-guarantor deferred to v2.

## Cross-cutting additions (apply to all proposals)

- **Mempool-tier classification header** — short table naming which flows land in which tier.
- **PQ-compatibility note** — one paragraph per proposal.
- **FOCIL-compatibility note** — one paragraph per proposal citing attester-facing invariants.
- **Stream-advance-on-inclusion rule** — normative invariant pinned in `2d-nonces.md`, cited in `permissions.md` and `guarantors.md`.

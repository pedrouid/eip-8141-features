# Compare, Consolidated EIP-8141 Expansion

_Delta map for the root `eip-8141.md` draft in this repo._

## Scope

This proposal is a consolidated expansion of the current EIP-8141 spec. It folds together Guarantors, keyed nonce streams, and signer binding into one PR-shaped document, with supporting assets under `assets/eip-8141/`.

Primary comparison points:

- Current EIP-8141: [`EIPS/eip-8141.md`](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md)
- Guarantors: [PR #11555](https://github.com/ethereum/EIPs/pull/11555/files)
- Keyed nonces: [PR #11598](https://github.com/ethereum/EIPs/pull/11598/files), draft EIP-8250

Upstream cleanup PRs already merged and absorbed into the baseline above: [#11621](https://github.com/ethereum/EIPs/pull/11621) (Frames cleanup, section-name restructuring), [#11652](https://github.com/ethereum/EIPs/pull/11652) (atomic batching with any frames), and the **expiry verifier frame** ([`EXPIRY_VERIFIER = address(0x8141)`](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md#expiry-verifier-frame), an in-spec `VERIFY` frame whose 8-byte `frame.data` is a deadline timestamp covered by `compute_sig_hash` and checked deterministically without simulating any other frame). Deltas below are stated against post-merge upstream.

## Compared To Current EIP-8141

The current spec defines frame transactions, `APPROVE`, default EOA verification, a canonical signature hash, per-frame execution, restrictive mempool prefixes, and the built-in expiry verifier frame. This proposal keeps that architecture but changes the transaction surface and authentication model.

Changed from current EIP-8141:

- Transaction payload gains `signer` (uint64). Deadlines are NOT added to the envelope; they route through the upstream [expiry verifier frame](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md#expiry-verifier-frame) instead.
- `tx.nonce` keeps its name, type (`uint64`), and position. Its meaning is `signer`-conditional: legacy account nonce when `signer == 0`, per-signer stream sequence when `signer != 0`. No envelope rename of `nonce`.
- `APPROVE` gains `APPROVE_GUARANTEE`, expanding approval flags from two scope bits to three.
- Atomic-batch flag moves from bit `2` to bit `3`.
- A frame signature hash is added at `TXPARAM(0x0B)` for guarantor signatures that must bind other VERIFY frame data. (Upstream's `0x09 = len(frames)` and `0x0A = currently executing frame index` are preserved; the new entry sits at `0x0B`.)
- `TXPARAM` gains entries for `signer` (`0x0C`) and pre-state legacy nonce (`0x0D`).
- Restrictive mempool replacement changes from `(sender, nonce)` to `(sender, signer, nonce)`.
- `AUTH_MANAGER` is introduced as a single system contract for authentication state.
- `ECRECOVER` gains a hit-path-first signer-binding lookup while preserving the secp256k1 miss path.

Unchanged from current EIP-8141:

- Frame modes remain `DEFAULT`, `VERIFY`, and `SENDER`.
- Existing opcodes remain the same; no new opcodes are introduced.
- Existing frame payload shape remains `[mode, flags, target, gas_limit, value, data]`.
- VERIFY frame data remains elided from the canonical signature hash.
- No account RLP encoding changes are introduced.

## Compared To Guarantors PR

PR #11555 adds a guarantor payer that can make a tx public-mempool admissible without simulating sender validation. This proposal keeps that core mechanism.

Kept from PR #11555:

- `APPROVE_GUARANTEE` as a distinct approval scope.
- `guarantor_approved` / payer state in transaction execution.
- Transaction validity via `guarantor_approved OR (sender_approved AND payer_approved)`.
- Canonical guarantor prefix in restrictive mempool policy.
- Frame signature hash for guarantor mode.
- Canonical paymaster asset extended to support paymaster mode and guarantor mode.

Changed from PR #11555:

- Sender nonce handling is replaced by per-signer nonce streams, so inclusion consumes `(sender, signer, nonce)` through `AUTH_MANAGER`.
- Guarantor replay discussion is integrated with keyed nonce semantics rather than relying only on the canonical paymaster's per-sender guarantor nonce.
- The canonical paymaster remains a guarantor asset, but global replay protection for the sender transaction is handled by the frame transaction's keyed nonce domain.
- The proposal adds signer binding after guarantor semantics, so the final `TXPARAM` table has more entries than PR #11555.

Main integration rule: Guarantors must stay the mempool-admission primitive. Flexible nonces and signer binding must not require public mempool nodes to simulate sender validation when a valid canonical guarantor prefix is present.

## Compared To Keyed Nonces PR

PR #11598 proposes EIP-8250 as a sibling EIP requiring EIP-8141. This proposal folds the keyed-nonce mechanism directly into the EIP-8141 expansion.

Kept from PR #11598:

- Payload adds `signer` (uint64) instead of PR #11598's `nonce_key` (uint256); existing `nonce` field is reinterpreted as the per-signer stream sequence when `signer != 0`. The rename and width drop are deliberate: `signer` is also the key of the registered signer entry in `AUTH_MANAGER`, and uint64 is enough for the per-account namespace once stream selectors are tied to registered signers rather than free-form keys. No envelope rename of `nonce`.
- `signer == 0` aliases the legacy account nonce path (no `AUTH_MANAGER` lookup).
- Non-zero per-signer streams live in protocol-managed system-contract storage.
- `nonce` stays `uint64`; `signer` is `uint64` (vs. PR #11598's `nonce_key: uint256`).
- First use of a non-zero signer is charged with `KEYED_NONCE_FIRST_USE_GAS = 20000`.
- `TXPARAM` exposes `signer` and pre-state legacy sender nonce.
- Replacement is keyed by `(sender, signer, nonce)`.

Changed from PR #11598:

- The system contract is named `AUTH_MANAGER`, not `NONCE_MANAGER`. The rename is load-bearing: a `NONCE_MANAGER` is a one-purpose registry, but `AUTH_MANAGER` is the canonical authentication-state contract for the account model. Keyed nonce streams and PQ signer registrations are both authentication state, and EIP-8141 needs the latter so accounts can use non-recoverable signature schemes (lattice, multivariate, hash-based) recognized by immutable `ECRECOVER` callers. Putting both behind one address means a single canonical contract carries the full identity surface for any signature scheme the protocol supports, present or future, instead of forking the upgrade into two parallel registries with two pubkey-resolution paths.
- `AUTH_MANAGER` stores both keyed nonce streams and signer registrations under one storage layout.
- `AUTH_MANAGER` has actual contract semantics in [`assets/eip-8141/AuthManager.sol`](../assets/eip-8141/AuthManager.sol), including `registerSigner` (account picks the `signer` id, must be non-zero), `clearSigner`, `getSigner`, `getNonce`, `checkNonce`, and `advanceNonce`.
- Keyed nonces are part of the same PR as Guarantors and signer binding rather than a separate EIP.
- The nonce-consumption rule is stated as successful inclusion regardless of sender VERIFY outcome, to compose with guarantor-backed txs.

Main integration rule: nonce streams and signer registrations are both authentication state. Pubkeys remain variables and calldata inputs, but account-facing terminology is signer-centric.

## New Beyond Those Specs

Signer binding is new relative to current EIP-8141, PR #11555, and PR #11598. It adds:

- Registered signers in `AUTH_MANAGER`.
- A tx-scoped `verified_signers` table.
- Binding VERIFY frames that prove `(digest, address)` claims under registered signer material.
- Modified `ECRECOVER`: table hit returns the bound address; miss follows existing secp256k1 behavior.
- `MAX_BOUND_SIGNERS = 8`.

## Deadlines: dropped from envelope, routed through upstream expiry verifier frame

Earlier revisions of this consolidated proposal added a `uint64 expiry` envelope field with a pre-frame consensus check, two ready/expired RBF rules, two JSON-RPC error codes, and `TXPARAM(0x0E)`. Upstream subsequently merged a built-in [expiry verifier frame](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md#expiry-verifier-frame) at `EXPIRY_VERIFIER = address(0x8141)`: an in-spec `VERIFY` frame whose 8-byte `frame.data` is the deadline timestamp, covered by `compute_sig_hash`, dropped from the public mempool deterministically when expired, with `TIMESTAMP` permitted only inside this frame's canonical runtime. The verifier-frame mechanism subsumes every load-bearing property the envelope-expiry design provided: consensus-enforced deadline, sig-hash coverage, deterministic ready/expired classification, no future-valid state, no simulation cost outside that one frame.

Folding deadlines into the envelope on top of this would mean paying the byte cost on every tx that does not use one, and forcing two parallel deadline paths through the spec (envelope check + verifier-frame check). The envelope `expiry` field, its pre-frame check, the `TXPARAM(0x0E)` exposure, the two JSON-RPC error codes, and the expired-eviction RBF rules are therefore dropped from this consolidated proposal. The standalone alternative [`proposals/envelope-expiry.md`](proposals/envelope-expiry.md) and its two-sided sibling [`proposals/validity-windows.md`](proposals/validity-windows.md) are preserved under `docs/proposals/` as comparison surface only; neither is part of the consolidated bundle.

## Assets

Current EIP-8141 has `assets/eip-8141/CanonicalPaymaster.sol`. This proposal changes assets to:

- `CanonicalPaymaster.sol`: adds guarantor mode, `APPROVE_GUARANTEE`, frame-signature-hash validation, and guarantor nonce support.
- `AuthManager.sol`: new single authentication-state system contract for keyed nonces and registered signers.

No separate nonce-manager or pubkey-registry asset is used. No expiry-related asset is needed: the upstream expiry verifier contract is part of the baseline.

# Glossary

_Single canonical definition per term used in this repo. Each entry tagged `(EIP-8141 base)` if the concept comes from EIP-8141 itself, `(introduced here)` if it is added by a proposal in this repo, or `(adjacent)` if it comes from a separate EIP / PR that the proposals build on._

## Transaction model

**Frame transaction** _(EIP-8141 base)_. The native account-abstraction transaction shape introduced by EIP-8141. A tx is a sequence of typed frames executed in order, each frame carrying a target, value, data, and a mode (VERIFY or SENDER).

**VERIFY frame** _(EIP-8141 base)_. A frame that runs an account's default code in a validation phase. Calls to `APPROVE` from a VERIFY frame set tx-scoped state (e.g., `payer_approved`, `guarantor`).

**SENDER frame** _(EIP-8141 base)_. A frame that executes user-intended action. `msg.sender` defaults to `tx.sender` (and to `execution_authority` if set, in Phase 2).

**Default code** _(EIP-8141 base)_. The protocol-supplied bytecode that runs in a VERIFY frame for an EOA that has not delegated to custom code. Default code is where standard tx authentication lives.

**APPROVE scope** _(EIP-8141 base; `guarantee` added by PR #11555)_. The opcode emitted by a VERIFY frame to set tx-scoped state. Scopes: `execution` (sender approved), `payment` (payer approved), `guarantee` (guarantor commitment).

**sighash** _(EIP-8141 base)_. The hash signed by the tx-level signature, computed by `compute_sig_hash`. VERIFY-frame `data` is elided; SENDER frames are not. See [`appendix/sighash-binding.md`](appendix/sighash-binding.md).

## Phase-1 primitives

**2D nonces** _(introduced here)_. Per-account parallel nonce streams keyed by `nonce_key`. Spec: [`phase-1/2d-nonces.md`](phase-1/2d-nonces.md).

**`nonce_key`** _(introduced here)_. Envelope field, `uint256`, default 0. Selects the nonce stream a tx sequences against. Key 0 is the legacy account-nonce path.

**Stream / lane** _(introduced here)_. Synonyms for one `(sender, nonce_key)` slot in `NonceLaneRegistry`. "Stream" emphasises the sequence of txs; "lane" emphasises the storage slot. Used interchangeably.

**`NonceLaneRegistry`** _(introduced here)_. Immutable system contract holding per-account per-key 64-bit sequence numbers. Spec: [`appendix/system-contracts.md`](appendix/system-contracts.md).

**Validity windows** _(introduced here)_. Envelope-level time bounds via `valid_after` / `valid_before`. Spec: [`phase-1/validity-windows.md`](phase-1/validity-windows.md).

**`valid_after` / `valid_before`** _(introduced here)_. Envelope fields, `uint64`, unix seconds; 0 = no bound. A tx is consensus-invalid if its inclusion timestamp falls outside the window.

**Signer binding** _(introduced here)_. Tx-scoped mechanism letting a PQ VERIFY frame bind `(digest, address)` claims that `ECRECOVER` resolves on subsequent calls within the same tx. Spec: [`phase-1/signer-binding.md`](phase-1/signer-binding.md).

**Pubkey hydration** _(deprecated; renamed)_. Old name for **signer binding**. The rename happened during research; treat any external reference to "pubkey hydration" as referring to the spec in [`phase-1/signer-binding.md`](phase-1/signer-binding.md).

**Verified-signers table** _(introduced here)_. The tx-scoped `set[(digest32, address)]` populated by binding VERIFY frames and queried by `ECRECOVER`. Spec: [`appendix/verified-signers.md`](appendix/verified-signers.md).

**`PubkeyRegistry`** _(introduced here)_. Immutable system contract holding per-account `(scheme, pubkey)` for PQ accounts. Spec: [`appendix/system-contracts.md`](appendix/system-contracts.md).

**Guarantor** _(adjacent, PR #11555)_. A tx-scoped role that commits to paying gas if sender VERIFY fails. Lets shared-state-read risk be priced as economic risk rather than mempool-policy risk. Spec: [`appendix/guarantors.md`](appendix/guarantors.md).

## Mempool tiers _(EIP-8141 base; vocabulary refined here)_

**Restrictive tier**. Public-mempool default. Deterministic checks; bounded reads against system contracts; no environmental opcodes during validation.

**Expansive tier**. Wider-mempool / opt-in propagation. Tolerates shared-state reads and environmental opcodes during validation.

**Private (direct-to-builder)**. Sent to specific builders out-of-band; no mempool propagation.

Reference: [`appendix/mempool-tiers.md`](appendix/mempool-tiers.md).

## Sighash binding analysis _(introduced here)_

**Class A binding**. Protocol-visible data whose validity depends only on the tx (e.g., `nonce_key`, `valid_after`). MUST be covered by the tx sighash; lives in the envelope.

**Class B binding**. Protocol-visible data whose validity depends on an independent account-side signature (e.g., a Phase-2 delegation bundle). Does not require tx-sighash coverage.

Reference: [`appendix/sighash-binding.md`](appendix/sighash-binding.md).

## Phase-2 vocabulary

**`execution_authority`** _(introduced for Phase 2)_. Tx-scoped state that, when set, makes SENDER frames execute with `msg.sender = execution_authority` instead of `tx.sender`. Spec: [`phase-2/execution-authority.md`](phase-2/execution-authority.md).

**`DelegationManager`** _(introduced for Phase 2)_. Immutable system contract verifying delegation bundles and emitting authoritative revocation events. Spec: [`phase-2/permissions.md`](phase-2/permissions.md).

**`validateAuth(digest, proof)`** _(introduced for Phase 2)_. Account-side authorization primitive. Crypto-agnostic and account-agnostic; replaces ERC-1271 in this repo's vocabulary.

## Repo conventions

**Phase 1 / Phase 2**. Phase 1 lands one of five alternatives plus guarantors. Phase 2 is a follow-on upgrade for delegated permissions. See [`docs/overview.md`](overview.md).

**Alternative ID**. `P1.N` (2D nonces), `P1.S` (signer binding), `P1.W` (validity windows), `P1.NS` (key lanes), `P1.NSW` (authorization scopes).

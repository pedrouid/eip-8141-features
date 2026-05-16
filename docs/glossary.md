# Glossary

_Single canonical definition per term used in this repo. Each entry tagged `(current EIP-8141)` if the concept comes from EIP-8141 itself, `(introduced here)` if it is added by a proposal in this repo, or `(adjacent)` if it comes from a separate EIP / PR that the proposals build on._

## Transaction model

**Frame transaction** _(current EIP-8141)_. The native account-abstraction transaction shape introduced by EIP-8141. A tx is a sequence of typed frames executed in order, each frame carrying a target, value, data, and a mode (VERIFY or SENDER).

**VERIFY frame** _(current EIP-8141)_. A frame that runs an account's default code in a validation phase. Calls to `APPROVE` from a VERIFY frame set tx-scoped state (e.g., `payer_approved`, `guarantor`).

**SENDER frame** _(current EIP-8141)_. A frame that executes user-intended action. `msg.sender` defaults to `tx.sender`.

**Default code** _(current EIP-8141)_. The protocol-supplied bytecode that runs in a VERIFY frame for an EOA that has not delegated to custom code. Default code is where standard tx authentication lives.

**APPROVE scope** _(current EIP-8141; guarantors proposed in PR #11555)_. The opcode emitted by a VERIFY frame to set tx-scoped state. Current scopes approve execution, payment, or both; this proposal adds `APPROVE_GUARANTEE` (`0x4`) as a fourth scope bit.

**sighash** _(current EIP-8141)_. The hash signed by the tx-level signature, computed by `compute_sig_hash`. VERIFY-frame `data` is elided; SENDER frames are not. See [`appendix/sighash-binding.md`](appendix/sighash-binding.md).

## Primitives

**Flexible nonces** _(introduced here; aka **2D nonces**)_. Per-account parallel nonce streams. The stream selector is `nonce_key` in the standalone proposal and `signer` in the aggregated proposals. Spec: [`proposals/flexible-nonces.md`](proposals/flexible-nonces.md).

**`nonce_key`** _(introduced here; standalone Flexible-nonces only)_. Envelope field, `uint256`, default 0. Selects the nonce stream a tx sequences against in `NonceManager`. Key 0 is the legacy account-nonce path.

**`signer`** _(introduced here; Key-streams / Auth-scopes / consolidated EIP)_. Envelope field, `uint64`, default 0. Selects a registered signer entry in `AuthManager` and the per-signer nonce stream. Replaces `nonce_key` in the AuthManager-using proposals because PQ pubkeys are too large to index protocol state directly; `signer` is the small uint64 indirection. Signer 0 is reserved for the legacy ECDSA / account-nonce path.

**Stream** _(introduced here)_. One `(sender, stream_selector)` slot of nonce state, where `stream_selector` is `nonce_key` standalone or `signer` aggregated.

**`NonceManager`** _(introduced here)_. Immutable system contract holding per-account per-key 64-bit sequence numbers. Used by the standalone Flexible-nonces alternative. Spec: [`appendix/system-contracts.md`](appendix/system-contracts.md).

**Expiry verifier frame** _(current EIP-8141; merged in upstream after this repo's first PR)_. Built-in `VERIFY` frame whose `frame.target == EXPIRY_VERIFIER = address(0x8141)` and whose 8-byte `frame.data` is a unix-seconds deadline covered by `compute_sig_hash`. Public mempool drops the tx deterministically once `block.timestamp > deadline`. Used by the consolidated EIP for any deadline use-case; supersedes the Envelope-expiry alternative below.

**Envelope expiry** _(introduced here; **comparison only**)_. Alternative shape adding a `uint64 expiry` envelope field. Subsumed by the upstream expiry verifier frame and dropped from the consolidated EIP. Preserved as comparison surface. Spec: [`proposals/envelope-expiry.md`](proposals/envelope-expiry.md).

**Validity windows** _(introduced here; **comparison only**)_. Two-sided envelope-level validity bounds via `valid_after` + `valid_before`. Subsumed by the upstream expiry verifier frame for the `valid_before` side; the `valid_after` (scheduled activation) component is out of scope for the consolidated EIP. Spec: [`proposals/validity-windows.md`](proposals/validity-windows.md).

**`expiry`** _(Envelope-expiry alternative only; not in the consolidated EIP)_. Envelope field, `uint64`, unix seconds; 0 = no bound. A tx is consensus-invalid if `block.timestamp >= expiry`.

**`valid_after`** _(Validity windows only; not in the consolidated EIP)_. Envelope field, `uint64`, unix seconds; 0 = no lower bound.

**`valid_before`** _(Validity windows only; not in the consolidated EIP)_. Envelope field, `uint64`, unix seconds; 0 = no upper bound.

**Signer binding** _(introduced here)_. Tx-scoped mechanism letting a PQ VERIFY frame bind `(digest, address)` claims that `ECRECOVER` resolves on subsequent calls within the same tx. Spec: [`proposals/signer-binding.md`](proposals/signer-binding.md).

**Verified-signers table** _(introduced here)_. The tx-scoped `map[digest32 -> address]` populated by binding VERIFY frames and queried by `ECRECOVER`. Spec: [`appendix/verified-signers.md`](appendix/verified-signers.md).

**`PubkeyRegistry`** _(introduced here)_. Immutable system contract holding per-account `(scheme, pubkey)` for PQ accounts. Used by the standalone Signer-binding alternative. Spec: [`appendix/system-contracts.md`](appendix/system-contracts.md).

**`AuthManager`** _(introduced here)_. Immutable system contract holding both keyed nonce streams and per-account signer entries `(scheme, pubkey)`. Replaces `NonceManager` + `PubkeyRegistry` in the Key-streams and Auth-scopes alternatives, and in the consolidated [`/eip-8141.md`](../EIPS/eip-8141.md) execution. Spec: [`appendix/system-contracts.md`](appendix/system-contracts.md). Reference impl: [`assets/eip-8141/AuthManager.sol`](../assets/eip-8141/AuthManager.sol).

**Guarantor** _(adjacent, [PR #11555](https://github.com/ethereum/EIPs/pull/11555))_. A tx-scoped role that commits to paying gas if sender VERIFY fails. Lets shared-state-read risk be priced as economic risk rather than mempool-policy risk. Spec: [`appendix/guarantors.md`](appendix/guarantors.md).

## Mempool tiers _(current EIP-8141; vocabulary refined here)_

**Restrictive tier**. Public-mempool default. Deterministic checks; bounded reads against system contracts; no environmental opcodes during validation.

**Expansive tier**. Wider-mempool / opt-in propagation. Tolerates shared-state reads and environmental opcodes during validation.

**Private (direct-to-builder)**. Sent to specific builders out-of-band; no mempool propagation.

Reference: [`appendix/mempool-tiers.md`](appendix/mempool-tiers.md).

## Sighash binding analysis _(introduced here)_

**Class A binding**. Protocol-visible data whose validity depends only on the tx (e.g., `nonce_key` / `signer`). MUST be covered by the tx sighash; lives in the envelope. Deadlines also fall in this class but the upstream expiry verifier frame carries them inside `frame.data` of a special `VERIFY` frame, which is exempted from VERIFY-data elision in `compute_sig_hash`, so they are sighash-covered without needing an envelope field.

**Class B binding**. Protocol-visible data whose validity depends on an independent signature chain (e.g., signer-binding claims verified under a registered PQ pubkey). Does not require tx-sighash coverage.

Reference: [`appendix/sighash-binding.md`](appendix/sighash-binding.md).

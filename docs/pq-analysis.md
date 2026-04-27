# PQ Signatures vs. ECRECOVER on the EVM — A reth-grounded analysis

_Scratch doc, not indexed on the site. Background analysis grounding the `pubkey-hydration.md` proposal in the actual implementation surface of a reference client (reth)._

## Where ECRECOVER is structurally baked into reth

**1. The transaction envelope carries no sender.**
`crates/ethereum/primitives/src/lib.rs:27`:
```rust
pub type TransactionSigned = alloy_consensus::EthereumTxEnvelope<TxEip4844>;
```
The envelope holds `(v, r, s)` only. The "from" address is *derived* from the signature, never transmitted, never stored in the tx itself. Every consumer assumes `recover_signer(tx) -> Address` is total and cheap-ish.

**2. A whole pipeline stage exists solely to amortize recovery.**
`crates/stages/stages/src/stages/sender_recovery.rs` runs ECDSA recovery over every historical tx, in 100-tx rayon chunks (`WORKER_CHUNK_SIZE`), and writes the result to a dedicated table:

```
table TransactionSenders { Key = TxNumber; Value = Address }
```

(`crates/storage/db-api/src/tables/mod.rs:496`). The comment is explicit: *"to speed up execution stage and allows fetching signer without doing transaction signed recovery."* Reth treats recovery as the single most expensive per-tx CPU cost outside of EVM itself; that's why it's a stage, not an inline call.

**3. `RecoveredBlock<B>` is the canonical shape passed into execution.**
`storage/provider`, the engine, payload builder, RPC (`debug`, `trace`), the tx-pool maintainer, and `Chain::transactions_ecrecovered` all pass `RecoveredBlock` / `Recovered<Tx>` around. The block + senders are bundled because the executor must not redo recovery per-call.

**4. The 0x01 precompile.**
The EVM-level `ECRECOVER` lives in revm (revm-precompile) and is consumed via `crates/evm` and `crates/revm`. Smart contracts (EIP-712, permit, account abstraction signature checks, multisigs) all call it. It returns 20 bytes (address), not a pubkey, because the ABI was designed around recovery.

**5. Address ↔ key is one-way.**
`address = keccak256(pubkey_uncompressed)[12:]`. Given an address you cannot get the pubkey. The recovery property of secp256k1 ECDSA is what makes this asymmetry tolerable: the chain doesn't need to know the pubkey *until* a signature shows up, at which point the pubkey falls out of `(r, s, v, hash)`.

## What PQ schemes structurally cannot do

Every NIST PQC signature scheme (ML-DSA / Dilithium, Falcon, SLH-DSA / SPHINCS+) has the API `verify(pk, msg, sig) -> bool`. None has a recover. There is no "recover the lattice basis from a signature." So:

- You cannot derive an address from a PQ signature.
- You cannot verify a PQ signature against an address; you can only verify against a `pk`.
- Anywhere reth/EVM today says "I have `(hash, r, s, v)`, give me the sender," there is no PQ analogue.

## What concretely breaks

**A. Tx envelope and the sender-recovery stage.**
`EthereumTxEnvelope` has no `pk` field. A PQ tx must either:

- carry the full `pk` in the envelope (sizes below), inflating mempool/state-witness/calldata, or
- reference a `pk` already stored on-chain at the account (one-time registration; first tx is the bootstrap problem).

The `SenderRecoveryStage` becomes either a no-op (if `from` is explicit) or an account-table lookup; the rayon parallelism that exists today buys you nothing because there's no math to do, but the bytes-on-disk story gets worse.

**B. Sizes vs. secp256k1.**

| Scheme        | Public key | Signature |
|---------------|-----------:|----------:|
| secp256k1     |  33 / 64 B |     65 B  |
| ML-DSA-44     |    1312 B  |   2420 B  |
| ML-DSA-65     |    1952 B  |   3309 B  |
| Falcon-512    |     897 B  |  ~666 B   |
| SLH-DSA-128s  |      32 B  |   7856 B  |

A 65-byte sig becomes a 1–10 KB blob. Reth's `TransactionSenders` table is 28 bytes/row today (`TxNumber` u64 + `Address` 20). Storing a `pk` per first-use account is hundreds–thousands of bytes per slot, not 20.

**C. The 0x01 precompile contract is broken at the ABI.**
`ECRECOVER(hash, v, r, s) -> address` returns an *address* derived by recovery. A PQ replacement *must* take a `pk` as input, *must* return a boolean (or 0/1 word), and *cannot* return an address; there is nothing to derive. Every Solidity contract that does `ecrecover(...) == owner` (permits, EIP-712, multisigs, EIP-1271 fallbacks, optimistic-rollup fault proofs, meta-transactions) needs a redesign, not a swap. The natural shape is a new precompile, e.g. `MLDSA_VERIFY(pk, msg, sig) -> {0,1}`, with the application owning the `pk ↔ identity` mapping out-of-band.

**D. Account model.**
EOAs today are *defined* by `keccak(pk)[12:]`. Without recovery, "EOA" stops making sense as a signature-only construct. The realistic migration path is everything-is-a-smart-account: EIP-7702 lets an EOA delegate to code that calls a PQ verifier precompile against a stored `pk`. ERC-4337 already separates signature scheme from address. Both already work *because* they don't lean on `ecrecover`'s recovery property; they lean on EIP-1271's `isValidSignature(hash, sig) -> magic`. PQ slots into 1271 cleanly. It does not slot into 0x01 cleanly.

**E. Gas and DoS surface.**
Verification cost is much higher than ECDSA recovery (~3000 gas today). ML-DSA verify is dominated by NTT + sampling; Falcon by FFT over Z[x]. Pricing must absorb the new cost *and* the calldata expansion. The mempool's per-tx CPU budget rises; reth's tx-pool validator (`crates/transaction-pool`) currently leans on `recover_signer` being fast enough to do per-arrival; PQ verify is the same order, but the *bytes* per arrival blow up bandwidth limits in `crates/net/network/src/transactions/mod.rs` (announcement size policies, sharded-mempool filters) faster than CPU does.

**F. Block witness / state proofs.**
Stateless clients and SSZ-ified consensus types include senders implicitly (recoverable from sig). With PQ, either each tx ships `pk` in the witness (size hit), or witnesses must include a Merkle proof of the account's stored `pk` (extra trie reads per tx). Reth's `RecoveredBlock` shape is fine; the wire format isn't.

## The minimum viable PQ-on-EVM-today shape

Given the above, the realistic "today" plan is *not* "replace ECRECOVER":

1. **New precompile**: `P256_VERIFY`-style, e.g. `MLDSA65_VERIFY(pk, msg_hash, sig)` returning a 32-byte boolean. RIP-7212 already set the precedent for `secp256r1` verify (returns bool, takes pk explicitly). PQ verify is the same shape, just with bigger inputs.
2. **Account abstraction does the identity binding.** EIP-7702 + 4337 wallets store the `pk` in account code/storage and call the verify precompile inside `validateUserOp` / `isValidSignature`. The protocol layer never has to learn how to recover from a PQ sig, because it can't.
3. **Tx-envelope-level PQ** (ML-DSA-signed transactions instead of EOA ECDSA) is a hard fork item: a new tx type that carries `pk` (or a pointer to a registered `pk`), and the consensus rule changes to verify rather than recover. In reth that means a new variant in `EthereumTxEnvelope` (or its successor), a `SenderRecoveryStage` that becomes a "fetch pk + verify" stage, and the `TransactionSenders` table either shrinks (sender is now explicit in the envelope) or grows (cache the verified-pk-keyed account).

## Summary

Reth's whole sender pipeline (the dedicated stage, the cache table, `RecoveredBlock`, and the 20-byte address ABI of the 0x01 precompile) assumes a one-shot `(sig, hash) → address` function. PQ schemes don't have that function, won't have it, and aren't getting it. So you can't drop-in replace ECRECOVER; you replace the *paradigm* with `verify(pk, msg, sig)` exposed as a new precompile, and you push identity binding up into account abstraction (EIP-7702 / ERC-4337 / EIP-1271). Anything that tries to keep recovery semantics is fighting the math.

The `pubkey-hydration.md` proposal threads this needle for EIP-8141: it does not try to keep recovery semantics for PQ accounts (the math forbids it); instead it lets a PQ VERIFY frame *prove* `(digest, address)` ahead of execution and lets `ECRECOVER` look the answer up. The 0x01 ABI keeps returning an address; the recovery step is replaced by a table consult populated from `verify(pk, msg, sig)` in a prior frame. That is what makes immutable contracts continue to work without a redesign of every `permit` site.

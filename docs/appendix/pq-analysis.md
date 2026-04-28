# PQ Signatures vs. ECRECOVER on the EVM

```
Canonical for:  NIST PQC + MAYO-2 sizing; reth pipeline grounding for PQ identity
Referenced by:  P1.S, P1.NS, P1.NSW; P2
```

_Background analysis grounding signer binding in the actual implementation surface of reth. All curve-specific sizing and scheme tradeoffs live here so the proposals can stay scheme-agnostic. Cited by [`phase-1/signer-binding.md`](../phase-1/signer-binding.md), [`phase-1/key-lanes.md`](../phase-1/key-lanes.md), [`phase-1/authorization-scopes.md`](../phase-1/authorization-scopes.md)._

## How ECRECOVER is baked into reth

Five facts from the reth codebase shape the problem:

1. **The transaction envelope carries no sender.** `TransactionSigned` (`crates/ethereum/primitives/src/lib.rs`) holds `(v, r, s)` only; "from" is *derived* from the signature, never transmitted, never stored. Every consumer assumes `recover_signer(tx) -> Address` is total and cheap-ish.
2. **A whole pipeline stage exists to amortise recovery.** `SenderRecoveryStage` (`crates/stages/stages/src/stages/sender_recovery.rs`) runs ECDSA recovery over every historical tx in 100-tx rayon chunks and writes results to a dedicated 28-byte-per-row `TransactionSenders` table. Recovery is reth's most expensive per-tx CPU cost outside of EVM itself.
3. **`RecoveredBlock<B>` is the canonical shape passed into execution.** Engine, payload builder, RPC, tx-pool maintainer — all pass block + senders bundled because the executor must not redo recovery per-call.
4. **The 0x01 precompile returns 20 bytes (address), not a pubkey,** because the ABI was designed around recovery. Smart contracts (EIP-712, permit, multisigs, EIP-1271 fallbacks) all call it.
5. **Address ↔ key is one-way.** `address = keccak256(pubkey)[12:]`. Given an address you cannot get the pubkey. The recovery property of secp256k1 ECDSA is what makes this asymmetry tolerable.

## What PQ schemes structurally cannot do

Every NIST PQC signature scheme has the API `verify(pk, msg, sig) -> bool`. None has a recover. There is no "recover the lattice basis from a signature." So:

- You cannot derive an address from a PQ signature.
- You cannot verify a PQ signature against an address; only against a `pk`.
- Anywhere reth/EVM today says "I have `(hash, r, s, v)`, give me the sender," there is no PQ analogue.

## Sizes vs. secp256k1

NIST PQC standardised three families (FIPS 203/204/205): ML-KEM (KEM, not relevant), ML-DSA, SLH-DSA, plus Falcon. The ongoing additional-signatures round includes MAYO (multivariate). Representative parameter sets:

| Scheme        | Family    | Public key | Signature  | Notes                                     |
|---------------|-----------|-----------:|-----------:|-------------------------------------------|
| secp256k1     | ECDSA     |  33 / 64 B |      65 B  | Reference                                 |
| ML-DSA-44     | Lattice   |    1312 B  |    2420 B  | NIST L1 (FIPS 204)                        |
| ML-DSA-65     | Lattice   |    1952 B  |    3309 B  | NIST L3                                   |
| ML-DSA-87     | Lattice   |    2592 B  |    4627 B  | NIST L5                                   |
| Falcon-512    | Lattice   |     897 B  |    ~666 B  | NTRU-based; smallest lattice signatures   |
| Falcon-1024   | Lattice   |    1793 B  |   ~1280 B  |                                           |
| SLH-DSA-128s  | Hash      |      32 B  |    7856 B  | Smallest pk; largest signatures (FIPS 205)|
| SLH-DSA-128f  | Hash      |      32 B  |   17088 B  |                                           |
| SLH-DSA-256s  | Hash      |      64 B  |   29792 B  |                                           |
| MAYO-1        | Multivar. |    1168 B  |     321 B  | NIST add'l-sigs round                     |
| MAYO-2        | Multivar. |    5488 B  |     180 B  | Smallest PQ signature in the table        |
| MAYO-3        | Multivar. |    2656 B  |     577 B  |                                           |
| MAYO-5        | Multivar. |    5008 B  |     838 B  |                                           |

A 65-byte secp256k1 sig becomes a 100 B–30 KB blob depending on scheme.

**Inline-in-envelope is impractical across the board.** Even MAYO-2, the smallest PQ signature (180 B), pairs that with a 5.4 KB pubkey. ML-DSA-65 needs ~2 KB of pubkey alongside its 3.3 KB signature. SLH-DSA pairs a 32 B pubkey with signatures that dwarf the rest of the envelope. Every scheme has at least one element measured in kilobytes; carrying both per-tx multiplies mempool bandwidth and witness size.

**Registry-based pubkey storage makes this tractable.** Storing the pubkey once (SSTORE-from-zero on first registration) and referencing it per-tx by account address bounds the per-tx cost to one storage-slot read against the registry's `storageRoot`, regardless of scheme. This is why signer binding rejects the inline-pubkey alternative. See [`appendix/system-contracts.md`](system-contracts.md) for the registry spec.

**Family tradeoffs**:

- **Lattice (ML-DSA, Falcon)**: balanced sizes, fast verify. Falcon has the smallest combined pk+sig (~1.5 KB) but harder constant-time implementation. ML-DSA is the conservative default.
- **Hash-based (SLH-DSA / SPHINCS+)**: tiny public keys, very large signatures, conservative security assumptions (only hash-function security needed). Bandwidth-bound.
- **Multivariate (MAYO)**: smallest PQ signatures (180–838 B) at the cost of larger pubkeys (1.2–5.5 KB). Newer; not yet NIST-standardised. Attractive for bandwidth-constrained per-tx footprints when pubkeys are stored once via registry.

## What concretely breaks beyond size

- **The 0x01 precompile is broken at the ABI.** `ECRECOVER(hash, v, r, s) -> address` returns an address derived by recovery. A PQ replacement must take a `pk`, return a boolean, and cannot return an address. Every Solidity site doing `ecrecover(...) == owner` (permits, multisigs, EIP-1271 fallbacks, optimistic-rollup fault proofs, meta-transactions) needs a redesign, not a swap.
- **The account model.** EOAs are *defined* by `keccak(pk)[12:]`. Without recovery, "EOA" stops making sense as a signature-only construct. EIP-7702 + ERC-4337 already separate signature scheme from address by leaning on EIP-1271's `isValidSignature(hash, sig) -> magic`; PQ slots in cleanly. It does not slot into 0x01 cleanly.
- **Gas and DoS.** Verification cost is much higher than ECDSA recovery (~3000 gas today). ML-DSA verify is dominated by NTT + sampling; Falcon by FFT over Z[x]; SLH-DSA by hash-tree traversal; MAYO by linear algebra over small fields. The mempool's per-tx CPU budget rises; bandwidth rises faster than CPU.
- **Block witnesses.** Stateless clients include senders implicitly (recoverable from sig). With PQ, either each tx ships `pk` in the witness or witnesses must include a Merkle proof of the account's stored `pk`. The wire format needs work; reth's `RecoveredBlock` shape is fine.

## Minimum viable PQ-on-EVM-today shape

Not "replace ECRECOVER":

1. **New precompile**, e.g. `MLDSA65_VERIFY(pk, msg_hash, sig)` returning a 32-byte boolean. RIP-7212 set the precedent for `secp256r1` verify.
2. **Account abstraction does the identity binding.** EIP-7702 + 4337 wallets store the `pk` in account storage and call the verify precompile inside `validateUserOp` / `isValidSignature`.
3. **Tx-envelope-level PQ** is a network upgrade item: a new tx type carrying a *pointer* to a registered `pk` (not the `pk` itself), with consensus verifying rather than recovering.

## How EIP-8141 signer binding threads the needle

Signer binding does not try to keep recovery semantics for PQ accounts (the math forbids it). Instead a PQ VERIFY frame proves `(digest, address)` ahead of execution and `ECRECOVER` looks the answer up. The 0x01 ABI keeps returning an address; the recovery step is replaced by a table consult populated from `verify(pk, msg, sig)` in a prior frame. Immutable contracts continue to work without redesign.

The mechanism is curve-independent: it needs only `verify(pk, msg, sig) -> bool` and an address-derivation rule per scheme. Concrete scheme parameters belong in the `signature_type` registry that ships alongside whichever Phase-1 alternative lands. The proposals themselves stay agnostic so that adding ML-DSA-65 today and MAYO-2 later doesn't require reopening the consensus spec.

See [`appendix/verified-signers.md`](verified-signers.md) for the verified-signers-table spec.

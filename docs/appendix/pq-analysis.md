# PQ Signatures vs. ECRECOVER on the EVM

```
Canonical for:  NIST PQC + MAYO-2 sizing; reth pipeline grounding for PQ identity
Referenced by:  Signer binding, Key streams, Auth scopes
```

_Background analysis grounding signer binding in the actual implementation surface of reth. All curve-specific sizing and scheme tradeoffs live here so the proposals can stay scheme-agnostic. Cited by [`signer-binding.md`](../proposals/signer-binding.md), [`key-streams.md`](../proposals/key-streams.md), [`auth-scopes.md`](../proposals/auth-scopes.md)._

## How ECRECOVER is baked into reth

Five facts from the reth codebase shape the problem:

1. **The transaction envelope carries no sender.** `TransactionSigned` (`crates/ethereum/primitives/src/lib.rs`) holds `(v, r, s)` only; "from" is *derived* from the signature, never transmitted, never stored. Every consumer assumes `recover_signer(tx) -> Address` is total and cheap-ish.
2. **A whole pipeline stage exists to amortise recovery.** `SenderRecoveryStage` (`crates/stages/stages/src/stages/sender_recovery.rs`) runs ECDSA recovery over every historical tx in 100-tx rayon chunks and writes results to a dedicated 28-byte-per-row `TransactionSenders` table. Recovery is reth's most expensive per-tx CPU cost outside of EVM itself.
3. **`RecoveredBlock<B>` is the canonical shape passed into execution.** Engine, payload builder, RPC, and tx-pool maintainer all pass block + senders bundled because the executor must not redo recovery per-call.
4. **The 0x01 precompile returns 20 bytes (address), not a pubkey,** because the ABI was designed around recovery. Smart contracts (EIP-712, permit, multisigs, EIP-1271 fallbacks) all call it.
5. **Address ↔ key is one-way.** `address = keccak256(pubkey)[12:]`. Given an address you cannot get the pubkey. The recovery property of secp256k1 ECDSA is what makes this asymmetry tolerable.

## What PQ schemes structurally cannot do

Every NIST PQC scheme has the API `verify(pk, msg, sig) -> bool`. None has a recover, **across all PQ families**. Lattice and multivariate are non-recoverable structurally: verification arithmetic requires the pubkey as input (`Az - ct1 ≈ w` in ML-DSA, `s1 + s2*h = c mod q` in Falcon, evaluating the public map in MAYO). Hash-based (SLH-DSA, SPHINCS+) is non-recoverable by design: SLH-DSA's message digest is `H_msg(R, PK.seed, PK.root, M)`, binding the pubkey into the first step of verification to defend against multi-target preimage attacks; no `(msg, sig)` pair lets you derive a candidate pubkey.

So you cannot derive an address from a PQ signature, you cannot verify a PQ signature against an address, and there is no PQ analogue of "I have `(hash, r, s, v)`, give me the sender."

**This is the load-bearing constraint behind signer binding.** The pubkey-size discussion below is a separate concern; it affects *how* pubkeys are made available, not *whether* a lookup is needed. A lookup is unavoidable for every PQ scheme.

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

A 65-byte secp256k1 sig becomes a 100 B-30 KB blob depending on scheme.

**Pubkey-size pressure is exclusive to lattice and multivariate.** Hash-based pubkeys (SLH-DSA: 32-64 B) are comparable to secp256k1. The kilobyte-scale pubkey problem is lattice (897 B-2.6 KB) and multivariate (1.2-5.5 KB). Per-tx *signatures* are a separate cost no registry shortcuts: hash-based sigs are kilobyte-scale (SLH-DSA-128f ≈ 17 KB), lattice and multivariate are 180 B-4.6 KB.

**Registry-based pubkey storage is the right call for all families.** Storing the pubkey once bounds per-tx cost to one signer-entry read regardless of scheme. Lattice and multivariate save kilobytes per tx. For hash-based the case is uniform interface, not size: supporting both pubkey-by-reference and pubkey-by-value forks the protocol into two binding chains, two mempool stories, and two RPC shapes. Forward compatibility matters: future schemes shouldn't relitigate the binding-chain decision. See [`appendix/system-contracts.md`](system-contracts.md).

**Family tradeoffs**:

- **Hash-based (SLH-DSA, SPHINCS+)**: tiny pubkeys, large signatures. Security from hash collision and preimage resistance only. Conservative pick; suited to cold-storage / treasury.
- **Lattice (ML-DSA, Falcon)**: balanced sizes, fast verify. Falcon has smallest combined pk+sig (~1.5 KB) but harder constant-time impl; ML-DSA is the default. Performant pick for hot wallets.
- **Multivariate (MAYO)**: smallest PQ signatures (180-838 B), larger pubkeys (1.2-5.5 KB). Not yet NIST-standardised. Attractive for bandwidth-bound per-tx footprints.

Operators may want different schemes per account profile. EIP-8141 stays scheme-agnostic; the `signature_type` registry supports the full set.

## What concretely breaks beyond size

- **The 0x01 precompile is broken at the ABI.** `ECRECOVER(hash, v, r, s) -> address` returns an address derived by recovery. A PQ replacement must take a `pk`, return a boolean, and cannot return an address. Every Solidity site doing `ecrecover(...) == owner` (permits, multisigs, EIP-1271 fallbacks, optimistic-rollup fault proofs, meta-transactions) needs a redesign.
- **The account model.** EOAs are *defined* by `keccak(pk)[12:]`. Without recovery, "EOA" stops making sense as a signature-only construct. EIP-7702 + ERC-4337 already separate signature scheme from address via EIP-1271's `isValidSignature(hash, sig) -> magic`; PQ slots in cleanly there, not into 0x01.
- **Gas and DoS.** Verification cost is much higher than ECDSA recovery (~3000 gas today). ML-DSA verify is NTT + sampling; Falcon is FFT over Z[x]; SLH-DSA is hash-tree traversal; MAYO is linear algebra. Mempool per-tx CPU rises; bandwidth rises faster than CPU.
- **Block witnesses.** Stateless clients include senders implicitly (recoverable from sig). With PQ, each tx either ships `pk` in the witness or witnesses include a Merkle proof of the account's stored `pk`. Wire format needs work; reth's `RecoveredBlock` shape is fine.

## Minimum viable PQ-on-EVM-today shape

Not "replace ECRECOVER":

1. **New precompile**, e.g. `MLDSA65_VERIFY(pk, msg_hash, sig)` returning a 32-byte boolean. RIP-7212 set the precedent for `secp256r1` verify.
2. **Account abstraction does the identity binding.** EIP-7702 + 4337 wallets store the `pk` and call the verify precompile inside `validateUserOp` / `isValidSignature`.
3. **Tx-envelope-level PQ** is a network upgrade: a new tx type carrying a *pointer* to a registered `pk`, with consensus verifying rather than recovering.

## How EIP-8141 signer binding threads the needle

Signer binding does not try to keep recovery semantics for PQ accounts (the math forbids it). Instead a PQ VERIFY frame proves `(digest, address)` ahead of execution and `ECRECOVER` looks the answer up. The 0x01 ABI keeps returning an address; the recovery step is replaced by a table consult populated from `verify(pk, msg, sig)` in a prior frame. Immutable contracts continue to work without redesign.

The mechanism is curve-independent: it needs only `verify(pk, msg, sig) -> bool` and an address-derivation rule per scheme. Concrete scheme parameters belong in the `signature_type` registry that ships alongside whichever alternative lands. The proposals themselves stay agnostic so that adding ML-DSA-65 today and MAYO-2 later doesn't require reopening the consensus spec.

## AuthManager storage cost per pubkey

The Solidity reference contract stores pubkeys as `bytes` (dynamic): one length slot plus `1 + ceil(len/32)` data slots per entry. A `getSigner` lookup touches all of them. Per scheme: SLH-DSA-128s = 2 slots, SLH-DSA-256s = 3, Falcon-512 = 30, MAYO-1 = 38, ML-DSA-44 = 42, Falcon-1024 = 58, ML-DSA-65 = 62, ML-DSA-87 = 82, MAYO-3 = 84, MAYO-5 = 158, MAYO-2 = 173. Clients pinning the Solidity contract MUST charge witness and access cost for the full per-entry slot count; clients implementing native behavior MUST publish their effective per-pubkey slot count and access-cost rule so mempool simulation cost is uniform across implementations.

See [`appendix/verified-signers.md`](verified-signers.md) for the verified-signers-table spec.

# Priorities

```
Canonical for:  Phase-1 ranking; load-bearing-weight argument; viable bundles under one-upgrade constraint
Referenced by:  README.md (TL;DR + how-to-review); CLAUDE.md (top-level docs); overview.md (companion link); P1.S, P1.NS, P1.NSW (ranked-as labels)
```

_Subjective companion to [`overview.md`](overview.md). Where the overview enumerates the five Phase-1 alternatives neutrally, this doc takes a position: what is load-bearing, what is reducible, what can be deferred, and which bundles are viable under the one-upgrade constraint. Reads as the minimum requirement, the middle ground, and the maximum that fits in one upgrade._

## The central claim of EIP-8141

EIP-8141 is the native AA upgrade. Its load-bearing contribution is structural, not ergonomic: it severs the protocol-level identification of an account from the secp256k1 ECDSA recovery property. Every Phase-1 feature in this repo is downstream of that severance.

The claim worth preserving under any compression of scope is therefore:

> Accounts must be able to nominate a pubkey-based signer in the transaction object, where the pubkey is identified by reference (selector or id), not by inlining the pubkey bytes.

Everything else in Phase 1 is incremental once that holds.

## One upgrade, one chance

Native AA changes the consensus surface. It ships through the all-cores upgrade pipeline, with cross-client review, audit, and activation cycles measured in years. EIP-8141 is the upgrade that lifts AA into the protocol. The expansion this repo proposes lands inside that upgrade or not at all.

There is no realistic second opportunity to add a `NonceLaneRegistry` later, no follow-on to slot validity windows into a tx envelope that already shipped, no third pass to retrofit the recovery path. Whatever Phase 1 bundles into this upgrade is what the protocol carries forward.

The decision is therefore not which Phase-1 alternative is best in isolation. It is: how many features can be defended in one cross-client review cycle, knowing the upgrade is one-shot.

## Why pubkey-based signers is load-bearing

Two facts make this the minimum requirement.

**The recovery property is curve-specific.** `address = keccak256(pubkey)[12:]` works because secp256k1 ECDSA admits a recovery operation: given `(hash, r, s, v)` you can reconstruct the public key, hash it, and check the result against an address. No NIST PQC scheme (ML-DSA, Falcon, SLH-DSA, MAYO) admits a recover operation. The API every PQ scheme exposes is `verify(pk, msg, sig) -> bool`. There is no PQ analogue of `ECRECOVER`.

**The 0x01 precompile is wired into immutable contracts.** `permit`, WETH, Uniswap V2 pairs, multisigs, EIP-1271 fallbacks, optimistic-rollup fault proofs, meta-transactions, all call `ecrecover(...) == owner`. Those contracts cannot be redeployed. If EIP-8141 ships without a way to bind a non-secp256k1 signer to an account that immutable contracts can recognise, PQ accounts remain locked out of the EVM long-tail regardless of how clean the new tx model is.

The conclusion is that signer binding via a pubkey registry is not a Phase-1 feature alongside others. It is the mechanism that lets the EIP-8141 model deliver on its own premise.

See [`appendix/pq-analysis.md`](appendix/pq-analysis.md) for the curve-level grounding and [`appendix/verified-signers.md`](appendix/verified-signers.md) for the lookup mechanism that lets `ECRECOVER` keep returning addresses.

## Why registry, not envelope

Pubkeys cannot be inlined in the transaction envelope. The size data:

| Scheme        | Pubkey   |
|---------------|---------:|
| secp256k1     | 33 / 64 B |
| SLH-DSA       | 32 / 64 B |
| Falcon-512    | 897 B    |
| MAYO-1        | 1168 B   |
| ML-DSA-44     | 1312 B   |
| Falcon-1024   | 1793 B   |
| ML-DSA-65     | 1952 B   |
| ML-DSA-87     | 2592 B   |
| MAYO-3        | 2656 B   |
| MAYO-5        | 5008 B   |
| MAYO-2        | 5488 B   |

A secp256k1 pubkey is 33 or 64 bytes. PQ pubkeys range from 32 B (SLH-DSA) to ~5.5 KB (MAYO-2). Future schemes are bounded above only by the implementation budget of the day. Inlining a kilobyte-scale pubkey on every transaction multiplies mempool bandwidth, witness size, and propagation cost, with no upside since the same pubkey is used across many transactions for the lifetime of the account.

The minimum primitive is therefore: store the pubkey once, reference it by selector. EIP-8141 must specify either:

1. A canonical system contract (the `PubkeyRegistry` pattern in [`appendix/system-contracts.md`](appendix/system-contracts.md)) holding `(account, scheme_id, pubkey_bytes)`, or
2. A future per-account state extension that holds the same data, indexed under the account's storage trie.

The registry option lands inside existing snap-sync, witness, and state-tree machinery without account-encoding changes; it is the conservative pick. The account-state-trie option is mentioned for completeness because it preserves the same property under a different storage layout. The **inline pubkey path is rejected unconditionally**: any compression of scope that keeps inline pubkeys reintroduces the size problem and forfeits forward compatibility with larger PQ schemes.

## Folding in 2D nonces

2D nonces are presented as a separate Phase-1 feature ([`phase-1/2d-nonces.md`](phase-1/2d-nonces.md)) backed by a dedicated `NonceLaneRegistry`. Under the one-upgrade constraint, a separate registry shipped later is not on the table: it would mean a second consensus rule on tx admission, a second mempool policy, a second RPC, and a second cross-client review cycle, none of which the Ethereum core-dev process is structured to absorb on a per-feature basis.

The only viable path is to fold 2D nonces into the same `PubkeyRegistry` that signer binding already requires. Each registry entry carries its own 64-bit sequence number; the pubkey selector doubles as the nonce-lane selector, and every registered signer is automatically its own stream.

```solidity
struct Entry {
    uint16 scheme;
    bytes  pubkey;
    uint64 seq;     // pubkey-indexed nonce stream
}
```

The pre-tx rule becomes a single registry consult: resolve the signer, check the per-entry sequence, advance it on inclusion. The stream-advance-on-inclusion invariant from [`appendix/guarantors.md`](appendix/guarantors.md) carries over unchanged, since advancement is keyed on the bound signer rather than on a free-form `nonce_key`. The same shape works under the account-state-trie variant.

If the upgrade ships signer binding with this `seq` field on day one, 2D nonces are deliverable. If it ships without, 2D nonces are not deliverable in this upgrade and not deliverable after it.

## Folding in validity windows

Validity windows ([`phase-1/validity-windows.md`](phase-1/validity-windows.md)) close the stale-signature gap. They are useful, FOCIL-friendly, and the smallest possible Phase-1 envelope change in isolation. They are not load-bearing for the central claim, but the same one-upgrade constraint applies: two envelope fields and a pre-tx time check land in this upgrade or not at all.

Wallet-side mitigations (short-lived intents, refresh on demand) and Phase-2 caveat-bound expiry cover most of the user-visible gap if windows are dropped. The decision is therefore whether the upgrade can absorb the additional envelope surface and pre-tx check in the same review cycle as signer binding and 2D nonces, not whether they can be added later.

## Three viable bundles

Under the one-upgrade constraint, the five alternatives in [`overview.md`](overview.md) collapse to three viable bundles:

- **P1.S (signer binding)**, the minimum requirement. `PubkeyRegistry`, verified-signers table, `ECRECOVER` hit-path-first lookup. No 2D nonces, no validity windows.
- **P1.NS (key lanes)**, the middle ground. Signer binding with a per-entry `seq` field, plus the `nonce_key` envelope field and per-lane mempool rules. One registry, two features.
- **P1.NSW (authorization scopes)**, the maximum. P1.NS plus validity windows. The most user-visible bundle achievable in one upgrade.

Standalone **P1.N** (2D nonces only) and **P1.W** (validity windows only) are not viable under this constraint. They ship a tx model that cannot accommodate PQ accounts on day one, and there is no second upgrade in which to add signer binding afterwards. They appear in `overview.md` for completeness; this doc rules them out.

The hierarchy: **P1.NSW is best, P1.NS is the middle ground, P1.S is the minimum.** The decision between them is review burden in one cycle, not feature pickability across cycles. P1.S is the answer to "what must be in this upgrade for EIP-8141 to deliver on its own premise"; P1.NS and P1.NSW are answers to "how much more can the same upgrade carry without losing review."

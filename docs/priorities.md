# Priorities

```
Canonical for:  alternative ranking; load-bearing-weight argument; viable bundles under one-upgrade constraint
Referenced by:  README.md (TL;DR + how-to-review); CLAUDE.md (top-level docs); overview.md (companion link)
```

_Subjective companion to [`overview.md`](overview.md). Where the overview enumerates the six alternatives neutrally, this doc takes a position: what is load-bearing, what is reducible, and which bundles are viable under the one-upgrade constraint. Reads as the minimum requirement, the middle ground, and the maximum that fits in one upgrade._

## The central claim of EIP-8141

EIP-8141 is the native AA upgrade. Its load-bearing contribution is structural, not ergonomic: it severs the protocol-level identification of an account from the secp256k1 ECDSA recovery property. Every feature in this repo is downstream of that severance.

The claim worth preserving under any compression of scope is therefore:

> Accounts must be able to nominate a pubkey-based signer in the transaction object, where the pubkey is identified by reference (selector or id), not by inlining the pubkey bytes.

Everything else is incremental once that holds.

## One upgrade, one chance

Native AA changes the consensus surface. It ships through the all-cores upgrade pipeline, with cross-client review, audit, and activation cycles measured in years. EIP-8141 is the upgrade that lifts AA into the protocol. The expansion this repo proposes lands inside that upgrade or not at all.

There is no realistic second opportunity to add a `NonceManager` later, no follow-on to slot an `expiry` field into a tx envelope that already shipped, no third pass to retrofit the recovery path. Whatever bundles into this upgrade is what the protocol carries forward.

The decision is therefore not which alternative is best in isolation. It is: how many features can be defended in one cross-client review cycle, knowing the upgrade is one-shot.

## Why pubkey-based signers is load-bearing

Two facts make this the minimum requirement.

**The recovery property is curve-specific.** `address = keccak256(pubkey)[12:]` works because secp256k1 ECDSA admits a recovery operation: given `(hash, r, s, v)` you can reconstruct the public key, hash it, and check the result against an address. No NIST PQC scheme (ML-DSA, Falcon, SLH-DSA, MAYO) admits a recover operation. The API every PQ scheme exposes is `verify(pk, msg, sig) -> bool`. There is no PQ analogue of `ECRECOVER`.

**The 0x01 precompile is wired into immutable contracts.** `permit`, WETH, Uniswap V2 pairs, multisigs, EIP-1271 fallbacks, optimistic-rollup fault proofs, meta-transactions, all call `ecrecover(...) == owner`. Those contracts cannot be redeployed. If EIP-8141 ships without a way to bind a non-secp256k1 signer to an account that immutable contracts can recognise, PQ accounts remain locked out of the EVM long-tail regardless of how clean the new tx model is.

The conclusion is that signer binding via a pubkey registry is not one feature alongside others. It is the mechanism that lets the EIP-8141 model deliver on its own premise.

See [`appendix/pq-analysis.md`](appendix/pq-analysis.md) for the curve-level grounding and [`appendix/verified-signers.md`](appendix/verified-signers.md) for the lookup mechanism that lets `ECRECOVER` keep returning addresses.

## Why registry, not envelope

Given recovery is unavailable, the protocol must look up the pubkey from somewhere. Two paths exist: store it once and reference it by selector (registry), or inline the pubkey bytes in every transaction. The size profile splits sharply by scheme family:

| Scheme        | Pubkey    | Family |
|---------------|----------:|--------|
| secp256k1     | 33 / 64 B | classical |
| SLH-DSA       | 32 / 64 B | hash-based |
| Falcon-512    | 897 B     | lattice |
| MAYO-1        | 1168 B    | multivariate |
| ML-DSA-44     | 1312 B    | lattice |
| Falcon-1024   | 1793 B    | lattice |
| ML-DSA-65     | 1952 B    | lattice |
| ML-DSA-87     | 2592 B    | lattice |
| MAYO-3        | 2656 B    | multivariate |
| MAYO-5        | 5008 B    | multivariate |
| MAYO-2        | 5488 B    | multivariate |

**Lattice and multivariate**: pubkeys are kilobyte-scale and the same pubkey serves many txs across an account's lifetime. Inlining multiplies mempool bandwidth, witness size, and propagation cost with no upside. The registry reads one storage slot per signer per tx and amortises the cost.

**Hash-based**: pubkeys are 32-64 B, comparable to secp256k1; size alone would not justify a registry. The registry is still the right call. Supporting both pubkey-by-reference (lattice, multivariate) and pubkey-by-value (hash-based) forks the protocol into two binding chains, two mempool admission stories, and two RPC shapes for one logical capability. The ~32 B per-tx saving doesn't justify that, especially when hash-based per-tx signatures are themselves kilobyte-scale (SLH-DSA-128f sig ≈ 17 KB) and the registry doesn't help with signatures regardless.

EIP-8141 must therefore specify either:

1. A canonical system contract (the `PubkeyRegistry` pattern in [`appendix/system-contracts.md`](appendix/system-contracts.md)) holding `(account, scheme_id, pubkey_bytes)`, or
2. A future per-account state extension that holds the same data, indexed under the account's storage trie.

The registry option lands inside existing snap-sync, witness, and state-tree machinery without account-encoding changes; it is the conservative pick. The **inline pubkey path is rejected unconditionally**: even where size permits it (hash-based), forking the protocol into two pubkey-resolution paths costs more than it saves, and forfeits forward compatibility with the schemes (lattice, multivariate) where size genuinely forbids inlining.

## Folding in Flexible nonces

Flexible nonces are presented as a separate feature ([`proposals/flexible-nonces.md`](proposals/flexible-nonces.md)) backed by a dedicated `NonceManager`. Under the one-upgrade constraint, a separate registry shipped later is not on the table: it would mean a second consensus rule on tx admission, a second mempool policy, a second RPC, and a second cross-client review cycle, none of which the Ethereum core-dev process is structured to absorb on a per-feature basis.

The only viable path is to fold Flexible nonces into the same authentication-state contract that signer binding already requires. The merged form is `AuthManager` ([`appendix/system-contracts.md`](appendix/system-contracts.md)): one address, one code-hash, two storage maps both keyed by `(address, signer)` where `signer: uint64` is provided by the account at registration. The standalone `nonce_key` (uint256) becomes `signer` (uint64) in the merged form because every active stream is tied to a registered signer; raw PQ pubkeys are too large to index protocol state directly, so `signer` is the small indirection that points to the entry holding the (potentially kilobyte-scale) pubkey. One canonical contract carries both signer entries and per-signer nonce streams.

The pre-tx rule is a single registry consult: check the per-signer sequence, advance it on inclusion. The stream-advance-on-inclusion invariant from [`appendix/guarantors.md`](appendix/guarantors.md) carries over unchanged.

If the upgrade ships signer binding with the nonce side on day one, Flexible nonces are deliverable. Otherwise they are not deliverable in this upgrade and not deliverable after it.

## Folding in envelope expiry

The time-bound feature closes the stale-signature gap. Two mutually-exclusive shapes: **Validity windows** ([`proposals/validity-windows.md`](proposals/validity-windows.md)) with both bounds; **Envelope expiry** ([`proposals/envelope-expiry.md`](proposals/envelope-expiry.md)) with only the upper bound. Not load-bearing for the central claim, but the one-upgrade constraint applies: whichever lands, lands now.

The choice is Envelope expiry. Every envelope field is paid by every tx, not just txs using it. `valid_before` (deadlines) is the dominant use-case across intents, swaps, liquidations, atomic swaps, async actions; `valid_after` (scheduled activation) is solvable offchain by deferring submission and ships a heavier surface (future-valid state, reverse-window rejection, four error codes vs. two, per-sender caps, gossip threshold). Keep the field that earns its envelope cost; drop the one that does not. Detail in [`proposals/envelope-expiry.md`](proposals/envelope-expiry.md) §3.

Auth scopes folds in Envelope expiry; Validity windows is preserved as comparison surface.

## Three viable bundles

Under the one-upgrade constraint, the six alternatives in [`overview.md`](overview.md) collapse to three viable bundles:

- **Signer binding**, the minimum requirement. `PubkeyRegistry`, verified-signers table, `ECRECOVER` hit-path-first lookup. No Flexible nonces, no envelope expiry.
- **Key streams**, the middle ground. Signer binding plus per-signer nonce stream, the `signer` envelope field (uint64), and per-signer mempool rules. One registry, two features.
- **Auth scopes**, the maximum. Key streams + envelope expiry. The most user-visible bundle in one upgrade.

Standalone **Flexible nonces**, **Validity windows**, and **Envelope expiry** are not viable under this constraint. They ship a tx model that cannot accommodate PQ accounts on day one, with no second upgrade in which to add signer binding afterwards. This doc rules them out.

The hierarchy: **Auth scopes is best, Key streams is the middle ground, Signer binding is the minimum.** The decision between them is review burden in one cycle, not feature pickability across cycles. Signer binding answers "what must be in this upgrade for EIP-8141 to deliver on its own premise"; Key streams and Auth scopes answer "how much more can the same upgrade carry without losing review."

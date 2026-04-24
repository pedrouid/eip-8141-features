# Wallet Developer Feedback on 2D Nonces, Permissions, and Validity Windows

Perspective: wallet / wallet-SDK developer evaluating whether these additions make account UX easier to ship, safer to expose to users, and practical to integrate across RPC providers, dapps, indexers, hardware wallets, and mobile clients.

## Executive assessment

The three proposals target the right pain points:

- **2D nonces** solve "one stuck transaction freezes the account" and make concurrent app sessions realistic.
- **Validity windows** give wallets a protocol-native way to limit stale signatures, stale swaps, auction orders, scheduled actions.
- **Permissions** are the missing bridge between native AA and the permission/session-key UX users already expect from smart wallets.

The revisions also fixed the most important correctness problems. Moving `nonce_key` into the envelope is the right wallet-facing design — explicit, signable, displayable, routable through SDKs. Permissions now uses an explicit `execution_authority` instead of pretending the sender model already supported it.

Main wallet concern: not whether features are useful (they are), but whether they can be made **predictable enough for wallets to expose safely**. Wallets need stable tx semantics, RPC support, simulation support, human-readable signing prompts, hardware-wallet parsability, reliable public-mempool behavior. A primitive that's technically valid but frequently routes through private builders or fails under provider differences is hard to productize.

**Product-facing ranking**:

1. **Validity windows should ship first.** Simple, easy to explain, immediately improves user safety.
2. **2D nonces are high-value** if RPC/mempool behavior is standardized with them. Without provider support, wallets struggle to use them safely.
3. **Permissions are most valuable for UX but easiest to get wrong.** Need constrained v1 semantics, strong display, revocation UX, and a clear answer on which flows are public-mempool-compatible.

## 2D Nonces

### Wallet value

Major UX improvement. Today one pending tx blocks every later action. Modern wallets have: a swap pending, a game session active, a subscription scheduled, a recovery/admin action queued, a dapp session permission request, an L2 bridge or settlement waiting. Independent nonce streams isolate these workflows.

### Required abstractions

Wallets expose nonce lanes as an internal resource, not raw numbers users manage:

| Lane type | Example strategy | User label |
|---|---|---|
| Default | `0` | Main account |
| Dapp session | hash(origin, session) | App session |
| Recovery/admin | reserved high-bit | Security action |
| Automation | hash(rule id) | Scheduled action |
| One-off ephemeral | random non-zero | One-time action |

Protocol shouldn't standardize labels, but wallets and SDKs need conventions. A future ERC should define namespace derivation so two wallets don't accidentally share a lane.

### RPC and provider requirements

The new method is necessary:

```
eth_getTransactionCountByKey(address, nonce_key, blockTag)
```

Wallets also need: pending count per key, tx lookup by `(sender, nonce_key, nonce)`, replacement status per key, error codes for "lane not found" / "lane allocation cost missing" / "too many active streams", `eth_estimateGas` behavior for first-use lane allocation, simulation including mempool pending state per key.

Without provider features, wallets struggle to track 2D-nonce txs reliably across vendors.

### Signing and hardware-wallet impact

Envelope placement is a win for hardware wallets. A signer can display `Nonce lane: 0x...; Sequence: 12`. But raw `uint256` values aren't human-readable. Wallets need a metadata layer.

Recommended prompts:
- `nonce_key == 0`: "Main sequence #N".
- Known wallet-created lanes: wallet label, dapp, sequence.
- Unknown lanes: warn.
- First-use non-zero: "opens a new activity lane (extra gas)".

### Mempool UX

2D nonces only help users if public infrastructure treats lanes consistently. Wallets need deterministic answers: can two lanes be pending via this provider, max active lane count, does the provider gossip future-valid lane txs, replacement rules, eviction. If every provider has different policy, UX degrades to "works on one RPC, fails on another." Spec or companion standards should recommend a public-txpool policy even if not consensus.

### Recommendation

Ship with: standard RPC for keyed reads; standard txpool error codes; wallet namespace guidance; hardware-wallet display requirements; clear gas-estimation for first lane use; documented default-lane fallback for wallets that don't support 2D nonces.

## Validity Windows

### Wallet value

Most immediately useful. Common cases:

- swaps valid for 60–120 s;
- limit orders until deadline;
- auction bids during a phase;
- scheduled payments valid after a future time;
- session-key redemptions bounded to a short window;
- cancellation/replacement flows with auto-expiring old sigs;
- mobile wallets that may broadcast after intermittent connectivity.

Today wallets simulate through dapp calldata, smart-account validation, or ERC-4337 `validUntil`/`validAfter`. Native validity windows are cleaner because every node can evaluate them without running account code.

### Signing UX

Easy to explain, but bound semantics matter:
- Local-time equivalents.
- Relative duration ("valid for 2 minutes").
- Warn on unusually long windows.
- Warn on already-expired or reverse windows before signing.
- For scheduled txs, surface "not valid before" clearly.

Spec should define zero consistently: `valid_after = 0` no lower bound; `valid_before = 0` no upper bound. Avoids "zero means expired" special case.

### RPC and txpool behavior

Surface clearly:
- Future-valid accepted but not gossiped.
- Future-valid rejected because too far in future.
- Expired dropped.
- Replacement accepted before activation.
- Replacement after expiry only by signing a new sequence.

Critical: error reporting. Rejection because `valid_after` too far away should be a distinct error, not a generic "transaction underpriced."

### Interaction with 2D nonces

Wallets surface: "Scheduled transaction on App Session lane, sequence #4. Later txs on this lane wait until it lands, is replaced, or expires. Other lanes unaffected." Good UX if wallets track it; confusing if dapps pick lanes without wallet coordination.

### Recommendation

Ship ASAP. Easy to expose, easy to understand, compatible with hardware signing, useful for security, low-risk for public-mempool validation. Include display guidance and txpool error codes in the wallet-facing spec.

## Permissions

### Wallet value

Biggest UX unlock: session keys without smart account deployment, dapp-scoped allowances, recurring payments, delegated game actions, AI-agent/automation keys, social/recovery flows, hardware-wallet-protected admin lanes, passkey daily limits with hardware-wallet fallback.

### Role clarity

Revised design has the right separation:

| Role | Meaning | Display |
|---|---|---|
| `tx.sender` | Delegate submitting, consuming tx nonce | "Submitted by" |
| `execution_authority` | Account whose authority runs SENDER frames | "Acts as" / "Spends from" |
| payer | Pays gas on success | "Gas paid by" |
| guarantor | Pays on validation failure | "Guarantees failed-validation gas" |
| manager | Contract validating delegation | "Permission manager" |

A prompt saying only "Bob is sending a transaction" is unsafe if the tx executes as Alice.

### Permission prompts

For user safety, display: who receives authority; what contracts may be called; what functions; max value/token spend; expiry; one-time or reusable; which nonce lane/session; whether it can pay gas; whether it can re-delegate; how to revoke.

v1 wisely disables payment delegation and re-delegation. Keep that — they make prompts much harder to reason about.

### Human-readable caveats

Biggest risk: opaque caveats. If the manager accepts arbitrary caveat contracts, wallets cannot safely render what the user is granting.

v1 canonical caveat vocabulary: target allowlist, function-selector allowlist, max native value, max ERC-20 amount, expiry, one-shot salt, frame-count limit, exact-call commitment. Arbitrary caveat contracts should be marked advanced and likely expansive/private/guarantor-backed.

### Revocation UX

Wallets need: `wallet_getPermissions`-style local inventory; chain-indexed manager queries; event indexing for `DelegationRedeemed` and revocation; emergency revoke-all; per-dapp revoke; expiry status; warning for delegations signed with pre-PQ keys after account migration.

If the manager doesn't provide easy enumeration, wallets maintain offchain inventories — acceptable for drafts, weak for user safety. Manager should emit canonical events and provide deterministic lookup by delegation hash.

### Public mempool expectations

Classify permission flows:

| Flow | Expectation |
|---|---|
| One-hop, stateless, execution-only | Public mempool candidate |
| Caveats reading external state | Guarantor or expansive/private |
| Stateful quotas / daily limits | v2 or expansive/private |
| Payment delegation | v2 |
| Re-delegation | v2 |

Expose to SDKs. Wallet tells dapp "public mempool compatible" or "requires private/guarantor route." Without this, dapps build flows that work in demos and fail in production.

### PQ migration

Long-lived ECDSA delegation = persistent vulnerability even after account adopts PQ. Wallet requirements: all permissions have expiry by default; warn on long-lived classical delegations; PQ migration surfaces "revoke old permissions" as a first-class step; manager digests include domain separation distinguishing schemes/versions; `validateAuth` supports hybrid sigs without changing permission format.

`validateAuth(digest, proof)` is the right abstraction. Concern is lifecycle: users must not unknowingly carry old ECDSA delegations into PQ-secured accounts.

### Recommendation

Treat permissions as a wallet-facing product standard, not only a protocol mechanism. For v1: one-hop only; execution-only; explicit expiry required; no re-delegation; no payment delegation; canonical caveat vocabulary; public-mempool profile limited to bounded/stateless caveats; strong revocation/event/indexing requirements.

Wallets can build good UX on that. Trying to include arbitrary caveat contracts, stateful quotas, payment delegation, guarantors, and re-delegation all at once makes prompts impossible to make safe.

## Cross-feature wallet flows

### Session key flow

1. Dapp requests session permission.
2. Wallet allocates a nonce lane for dapp/session.
3. Wallet signs delegation with target/function/value caveats + expiry.
4. Dapp redeems with `tx.sender = session key`.
5. SENDER frames execute as user via `execution_authority`.
6. Validity windows bound each redemption attempt.
7. User revokes from wallet dashboard.

This depends on all three proposals composing cleanly.

### Swap flow

Dedicated or default lane; `valid_before` 60–120 s; exact target/function/value caveats; public route if stateless; private/guarantor if external state reads. Validity windows especially important — stale swaps are a common source of user harm.

### Recovery / admin flow

Reserved high-priority / admin lane for security actions (revoke, rotate keys, migrate to PQ, deactivate old keys, recover). Not blocked by app sessions or automation. One of the strongest wallet arguments for 2D nonces.

## SDK requirements

Primitives wallet and dapp SDKs need:

```ts
wallet_prepareFrameTransaction({ nonceKey, validAfter, validBefore, frames })
wallet_createPermission({ delegate, caveats, expiry, nonceKeyPolicy })
wallet_revokePermission({ delegationHash })
wallet_getNonceByKey({ address, nonceKey, blockTag })
```

Typed JSON schemas for: nonce lane metadata, validity windows, delegation digest, caveat descriptors, revocation records, simulation result with role breakdown. If every wallet invents these independently, dapps face the same fragmentation native AA is trying to avoid.

## Hardware wallet requirements

Need deterministic, bounded parsing. Avoid requiring hardware wallets to parse arbitrary manager calldata:

- Envelope fields (`nonce_key`, `valid_after`, `valid_before`) parsed natively.
- Permission digests use typed structured data with canonical caveat descriptors.
- Arbitrary caveats require blind-signing warnings unless the HW wallet recognizes the type.
- Role fields displayed explicitly: delegate, delegator, payer, guarantor.
- Unknown nonce lanes displayed as unknown.

2D nonces and validity windows are HW-friendly. Permissions are HW-friendly only if v1 caveats are canonical and structured.

## Bottom line

Revised proposals moving in the right direction for wallet devs.

- **Validity windows**: clear yes. Safest and easiest to expose.
- **2D nonces**: strong yes if RPC, txpool behavior, and lane conventions ship with the protocol work.
- **Permissions**: yes only with a narrow v1 and strong display/revocation standards. Protocol design is coherent; wallet safety depends on users understanding exactly what authority they're granting.

For wallet adoption, the key principle is predictability. Wallets handle new envelope fields, nonce lanes, delegated execution. Wallets cannot safely handle underspecified provider behavior, opaque caveats, inconsistent mempool routing, or permissions that cannot be displayed and revoked.

Best path: ship validity windows; ship 2D nonces with RPC and lane conventions; ship permissions as a constrained human-readable v1; add richer caveats, guarantors, payment delegation, and re-delegation only after wallets have safe rendering and revocation infrastructure.

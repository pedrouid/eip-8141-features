# Wallet Developer Feedback on 2D Nonces, Permissions, and Validity Windows

Perspective: wallet / wallet-SDK developer evaluating whether these EIP-8141 additions make account UX easier to ship, safer to expose to users, and practical to integrate across RPC providers, dapps, indexers, hardware wallets, and mobile clients.

## Executive assessment

From a wallet perspective, the three proposals target exactly the right pain points:

- **2D nonces** solve the "one stuck transaction freezes the account" problem and make concurrent app sessions realistic.
- **Validity windows** give wallets a protocol-native way to limit stale signatures, stale swaps, auction orders, and scheduled actions.
- **Permissions** are the missing bridge between native account abstraction and the permission/session-key UX that users already expect from smart wallets.

The revisions also fixed the most important correctness problems from the previous feedback. Moving `nonce_key` into the envelope is the right wallet-facing design: it is explicit, signable, displayable, and easy to route through SDKs. The permissions rewrite is also much clearer now that delegated execution uses an explicit `execution_authority` instead of pretending the existing sender model already supported it.

The main wallet concern is not whether these features are useful. They are. The concern is whether they can be made **predictable enough for wallets to expose safely**. Wallets need stable transaction semantics, RPC support, simulation support, human-readable signing prompts, hardware-wallet parsability, and reliable public-mempool behavior. A protocol primitive that is technically valid but frequently routes through private builders or fails under provider differences is hard to productize.

My product-facing ranking:

1. **Validity windows should ship first.** They are simple, easy to explain, and immediately improve user safety.
2. **2D nonces are high-value and should ship if RPC/mempool behavior is standardized with them.** Without provider support, wallets will struggle to use them safely.
3. **Permissions are the most valuable for UX but also the easiest to get wrong.** They need constrained v1 semantics, strong wallet display standards, revocation UX, and a clear answer on which flows are public-mempool-compatible.

## What Changed Since the Previous Feedback

### 2D nonces

The updated 2D nonce draft is much more wallet-friendly:

- `nonce_key` is now an envelope field, so wallets can sign it directly.
- `tx.nonce` remains the sequence, so existing wallet mental models survive.
- `eth_getTransactionCountByKey(address, nonce_key, blockTag)` avoids overloading legacy RPC.
- RBF is defined per `(sender, nonce_key, nonce)`, which is exactly what wallets need for replacement UX.
- First-use lane cost is acknowledged at consensus level, so wallets can estimate the cost of opening a new stream.

This fixes the earlier design's biggest wallet problem: invisible nonce metadata inside VERIFY calldata would have been hard for hardware wallets, signing libraries, dapp SDKs, transaction decoders, and users to reason about.

### Permissions

The permissions proposal now acknowledges the real wallet UX model:

- the delegate signs and submits,
- the delegator is the execution authority,
- payer/sponsor may be a third role,
- guarantor may be a fourth role.

That maps well to wallet UI because the roles can be displayed separately. The previous version blurred those roles, which would have made signing prompts unsafe.

The `validateAuth(digest, proof)` direction is also good for wallets. It avoids hardcoding ERC-1271 and lets wallets move from ECDSA to passkeys, hybrid signatures, or post-quantum schemes without changing the permission model.

### Validity windows

Moving validity bounds into the envelope is the right wallet-facing decision. A wallet can show:

```text
Valid after: 2026-04-24 10:00
Valid until: 2026-04-24 10:05
```

and know those bounds are enforced by consensus, not by a bundler, dapp, paymaster, or VERIFY-frame convention.

## 2D Nonces

### Wallet value

2D nonces are a major UX improvement. Today, one pending transaction can block every later action from the account. That is a bad fit for modern wallets, where a user might have:

- a swap pending,
- a game session active,
- a subscription payment scheduled,
- a recovery/admin action queued,
- a dapp requesting a session permission,
- an L2 bridge or settlement transaction waiting.

Independent nonce streams let wallets isolate these workflows. A stuck swap should not block a recovery action. A game session should not block the user's normal account lane. A scheduled transaction should not freeze all future activity.

### Required wallet abstractions

Wallets will need to expose nonce lanes as an internal resource, not as raw numbers users manage manually.

Recommended wallet model:

| Lane type | Example `nonce_key` strategy | User-facing label |
|---|---|---|
| Default | `0` | Main account activity |
| Dapp session | hash of dapp origin + session id | App session |
| Recovery/admin | reserved high-bit namespace | Security action |
| Automation | hash of automation rule id | Scheduled action |
| One-off ephemeral | random non-zero key | One-time action |

The protocol should not standardize labels, but wallets and SDKs need a convention. A future ERC should define namespace derivation so two wallets do not accidentally use the same lane for unrelated purposes.

### RPC and provider requirements

The new RPC method is necessary:

```text
eth_getTransactionCountByKey(address, nonce_key, blockTag)
```

But wallets need more than that. To productize 2D nonces, providers should also support:

- pending count per key,
- transaction lookup by `(sender, nonce_key, nonce)`,
- replacement status per key,
- error codes for "lane not found", "lane allocation cost missing", and "too many active streams",
- clear `eth_estimateGas` behavior for first-use lane allocation,
- simulation that includes current mempool pending state for that key.

Without those provider features, wallets can still sign 2D nonce transactions, but they will struggle to track them reliably across RPC vendors.

### Signing and hardware-wallet impact

Envelope placement is a win for hardware wallets. A signer can display:

```text
Nonce lane: 0x...
Sequence: 12
```

That said, raw `uint256 nonce_key` values are not human-readable. Wallets need a metadata layer. If a hardware wallet shows only a 32-byte hex lane, most users cannot evaluate it.

Recommended signing prompt behavior:

- For `nonce_key == 0`: show "Main sequence #N".
- For known wallet-created lanes: show the wallet label, dapp, and sequence.
- For unknown lanes: show a warning that this transaction uses an unfamiliar nonce lane.
- For first-use non-zero lanes: show that the transaction opens a new activity lane and may cost extra gas.

### Mempool UX

2D nonces only help users if public infrastructure treats lanes consistently. Wallets need deterministic answers to:

- Can two lanes be pending at once through this RPC provider?
- What is the max active lane count?
- Does this provider gossip future-valid lane transactions?
- How does replacement work if the old tx is future-valid?
- Does the provider evict inactive lanes differently?

If every provider has a different active-stream policy, wallet UX will degrade into "works on one RPC, fails on another." The EIP or companion standards should specify a recommended public txpool policy, even if it is not consensus.

### Recommendation

Wallets should strongly support 2D nonces, but only if the feature ships with:

1. A standard RPC method for keyed nonce reads.
2. Standard txpool error codes.
3. Wallet namespace guidance for lane derivation.
4. Hardware-wallet display requirements.
5. Clear gas-estimation semantics for first lane use.
6. A documented default-lane fallback for wallets that do not support 2D nonces.

Without those, the protocol feature is good but the integration surface will fragment.

## Validity Windows

### Wallet value

Validity windows are the most immediately useful of the three proposals. Wallets routinely need to prevent stale signatures from being mined later than the user intended.

Common wallet cases:

- swaps valid for 60-120 seconds,
- limit orders valid until a deadline,
- auction bids valid only during a phase,
- scheduled payments valid after a future time,
- session-key redemptions bounded to a short window,
- cancellation/replacement flows where old signatures should expire automatically,
- mobile wallets that may broadcast after intermittent connectivity.

Today wallets simulate this through dapp calldata, smart-account validation, or ERC-4337 `validUntil`/`validAfter`. Native validity windows are cleaner because every node can evaluate them without running account code.

### Signing UX

Validity windows are easy to explain, but the exact bound semantics matter. Wallets should not have to explain off-by-one rules.

Recommended user-facing behavior:

- Show local-time equivalents.
- Show relative duration: "valid for 2 minutes".
- Warn on unusually long windows.
- Warn on already-expired or reverse windows before signing.
- For scheduled transactions, show "not valid before" clearly.

The spec should define zero consistently:

```text
valid_after = 0   no lower bound
valid_before = 0  no upper bound
```

That is easiest for wallets and avoids a confusing "zero means expired" special case.

### RPC and txpool behavior

Wallets need txpool behavior that can be surfaced clearly:

- future-valid tx accepted but not gossiped yet,
- future-valid tx rejected by public mempool because it is too far in the future,
- expired tx dropped,
- replacement accepted before activation time,
- replacement accepted after expiry only by signing a new nonce/sequence transaction.

The most important implementation detail is error reporting. If an RPC rejects a transaction because `valid_after` is too far away, the wallet should get a distinct error, not a generic "transaction underpriced" or "invalid transaction".

### Interaction with 2D nonces

Wallets will need to show that a future-valid tx occupies its lane position. Example:

```text
Scheduled transaction on App Session lane, sequence #4.
Later transactions on this lane wait until it lands, is replaced, or expires.
Other lanes are unaffected.
```

This is a good UX if wallets can track it. It is confusing if dapps pick nonce lanes themselves without wallet coordination.

### Recommendation

Ship validity windows as soon as possible. They are:

- easy for wallets to expose,
- easy for users to understand,
- compatible with hardware signing,
- useful for security,
- low-risk for public mempool validation.

The wallet-facing spec should include display guidance and txpool error codes, but the protocol primitive itself is straightforward.

## Permissions

### Wallet value

Permissions are the biggest UX unlock:

- session keys without deploying a smart account,
- dapp-scoped allowances,
- recurring payments,
- delegated game actions,
- AI-agent or automation keys,
- social/recovery flows,
- hardware-wallet-protected admin lanes,
- passkey daily limits with hardware-wallet high-value fallback.

If done well, native permissions let wallets provide smart-wallet UX without forcing every user through account deployment, bundlers, EntryPoint compatibility, and per-chain smart-account fragmentation.

### Role clarity

The revised design has the right role separation:

| Role | Meaning | Wallet display requirement |
|---|---|---|
| `tx.sender` | Delegate submitting and consuming tx nonce | "Submitted by" |
| `execution_authority` | Account whose authority is used for SENDER frames | "Acts as" / "Spends from" |
| payer | Account paying gas on success | "Gas paid by" |
| guarantor | Account paying if validation fails | "Guarantees failed validation gas" |
| manager | Contract validating delegation | "Permission manager" |

Wallets need this separation. A prompt that says only "Bob is sending a transaction" is unsafe if the transaction actually executes as Alice.

### Permission prompt requirements

For user safety, wallet prompts must show a permission in terms users understand:

- who receives authority,
- what contracts may be called,
- what functions may be called,
- maximum value / token spend,
- expiry,
- whether it is one-time or reusable,
- which nonce lane/session it uses,
- whether it can pay gas,
- whether it can re-delegate,
- how to revoke it.

The v1 proposal wisely disables payment delegation and re-delegation. Wallets should strongly prefer that. Payment delegation and re-delegation are advanced features that make prompts much harder to reason about.

### Human-readable caveats

The largest wallet risk is opaque caveats. If the manager accepts arbitrary caveat contracts, wallets cannot safely render what the user is granting.

For v1, I would recommend a small canonical caveat vocabulary:

- target allowlist,
- function selector allowlist,
- max native value,
- max ERC-20 amount,
- expiry,
- one-shot salt,
- frame-count limit,
- exact-call commitment.

Arbitrary caveat contracts should be marked advanced and likely expansive/private/guarantor-backed. Wallets can support them eventually, but not as the default permission UX.

### Revocation UX

Permissions are only safe if users can see and revoke them.

Wallets need:

- `wallet_getPermissions`-style local inventory,
- chain-indexed manager queries,
- event indexing for `DelegationRedeemed` and revocation,
- emergency revoke-all,
- per-dapp revoke,
- expiry status,
- warning for delegations signed with pre-PQ / classical keys after account migration.

If the canonical manager does not provide easy enumeration, wallets will have to maintain offchain inventories. That is acceptable for drafts, but weak for user safety. At minimum, the manager should emit canonical events and provide deterministic lookup by delegation hash.

### Public mempool expectations

Wallets need to know whether a permission redemption will propagate publicly. The proposal should classify permission flows:

| Permission flow | Wallet expectation |
|---|---|
| One-hop, stateless caveats, execution-only | Public mempool candidate |
| Caveats reading external state | Guarantor or expansive/private |
| Stateful quotas / daily limits | v2 or expansive/private unless manager-native and bounded |
| Payment delegation | v2 |
| Re-delegation | v2 |

This should be exposed to SDKs. A wallet should be able to tell a dapp:

```text
This permission can be redeemed through the public mempool.
```

or:

```text
This permission requires a private/guarantor route.
```

Without that, dapps will build flows that work in demos and fail in production.

### Post-quantum migration

Permissions need special care in a PQ migration. A long-lived delegation signed with ECDSA is a persistent vulnerability even if the account later adopts PQ validation.

Wallet requirements:

- all permissions should have expiry by default,
- wallets should warn on long-lived classical delegations,
- PQ migration should surface "revoke old permissions" as a first-class step,
- manager digests should include enough domain separation to distinguish signature schemes and manager versions,
- `validateAuth` should support hybrid signatures without changing permission format.

The `validateAuth(digest, proof)` primitive is the right abstraction. The wallet concern is lifecycle management: users must not unknowingly carry old ECDSA delegations into a PQ-secured account.

### Recommendation

Permissions should be treated as a wallet-facing product standard, not only a protocol mechanism.

For v1, keep it narrow:

1. One-hop only.
2. Execution-only.
3. Explicit expiry required.
4. No re-delegation.
5. No payment delegation.
6. Canonical caveat vocabulary.
7. Public-mempool profile limited to bounded/stateless caveats.
8. Strong revocation/event/indexing requirements.

Wallets can build good UX on that. If v1 tries to include arbitrary caveat contracts, stateful quotas, payment delegation, guarantors, and re-delegation all at once, prompts become impossible to make safe.

## Cross-Feature Wallet Flows

### Session key flow

A good wallet flow would look like:

1. Dapp requests a session permission.
2. Wallet allocates a nonce lane for that dapp/session.
3. Wallet signs a delegation with target/function/value caveats and expiry.
4. Dapp redeems using `tx.sender = session key`.
5. SENDER frames execute as the user via `execution_authority`.
6. Validity windows bound each redemption attempt.
7. User can revoke the permission from the wallet dashboard.

This is the UX promise. It depends on all three proposals composing cleanly.

### Swap flow

For a swap, wallets should use:

- a dedicated lane or default lane depending on user setting,
- `valid_before` around 60-120 seconds,
- exact target/function/value caveats for any delegated executor,
- public-mempool route if caveats are stateless,
- private/guarantor route if the flow requires external state reads.

Validity windows are especially important here because stale swaps are a common source of user harm.

### Recovery/admin flow

Wallets should reserve a high-priority/admin lane for security actions:

- revoke permissions,
- rotate keys,
- migrate to PQ validation,
- deactivate old keys,
- recover account.

This lane should not be blocked by app sessions or automation flows. That is one of the strongest wallet arguments for 2D nonces.

## SDK Requirements

Wallet and dapp SDKs will need primitives roughly like:

```ts
wallet_prepareFrameTransaction({
  nonceKey,
  validAfter,
  validBefore,
  frames,
})

wallet_createPermission({
  delegate,
  caveats,
  expiry,
  nonceKeyPolicy,
})

wallet_revokePermission({
  delegationHash,
})

wallet_getNonceByKey({
  address,
  nonceKey,
  blockTag,
})
```

The standards work should include typed JSON schemas for:

- nonce lane metadata,
- validity windows,
- delegation digest,
- caveat descriptors,
- revocation records,
- simulation result with role breakdown.

If every wallet invents these schemas independently, dapps will face the same fragmentation that native AA is trying to avoid.

## Hardware Wallet Requirements

Hardware wallets need deterministic, bounded parsing. The proposals should avoid requiring hardware wallets to parse arbitrary manager calldata to understand what is being signed.

Recommended approach:

- Envelope fields (`nonce_key`, `valid_after`, `valid_before`) are parsed natively.
- Permission digests use typed structured data with canonical caveat descriptors.
- Arbitrary caveats require blind-signing warnings unless the hardware wallet recognizes the caveat type.
- Role fields are displayed explicitly: delegate, delegator, payer, guarantor.
- Unknown nonce lanes are displayed as unknown lanes.

The 2D nonce and validity-window designs are hardware-wallet-friendly. Permissions can be hardware-wallet-friendly only if v1 caveats are canonical and structured.

## Bottom Line

The revised proposals are moving in the right direction for wallet developers.

- **Validity windows** are a clear yes. They are the safest and easiest feature to expose.
- **2D nonces** are a strong yes if RPC, txpool behavior, and wallet lane conventions ship with the protocol work.
- **Permissions** are a yes only with a narrow v1 and strong display/revocation standards. The protocol design is now coherent, but wallet safety depends on users understanding exactly what authority they are granting.

For wallet adoption, the key principle is predictability. Wallets can handle new envelope fields, new nonce lanes, and delegated execution. They cannot safely handle underspecified provider behavior, opaque caveats, inconsistent mempool routing, or permissions that cannot be displayed and revoked.

The best path is:

1. Ship validity windows.
2. Ship 2D nonces with RPC and lane conventions.
3. Ship permissions as a constrained, human-readable v1.
4. Add richer caveats, guarantors, payment delegation, and re-delegation only after wallets have safe rendering and revocation infrastructure.

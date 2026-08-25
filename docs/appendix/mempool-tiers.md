# Mempool Tiers

## Public restrictive tier

Uses current EIP-8141 validation-prefix rules.

| Feature | Treatment |
|---|---|
| Canonical self relay | Existing prefix simulation/direct evaluation |
| Canonical paymaster | Existing code-match exception and payer reservation |
| Canonical guarantor | Code-match guarantee prefix; sender validation not simulated |
| Signer binding | Normally after payer approval, outside prefix simulation |
| Native keyed nonces | One-pending-sender rule until keyed concurrency is resolved |
| Expiry verifier | Existing deterministic drop rule |
| Nonceless | Native `(sender, replay_id)` identity, bounded deadline, and replay-state revalidation |

## Expansive tier

Nodes may admit account or paymaster validation with wider state dependencies, provided those transactions are not propagated as restrictive-tier transactions. Signer-binding frames can use arbitrary account logic after payment approval without changing public-prefix invalidation bounds.

## Private builder path

Private submission may use any consensus-valid frame structure. It does not waive guarantor replay, signer-binding conflict/cap, or nonceless consensus replay rules.

## Payer exposure

Every tier must prevent unbounded pending exposure against one payer. Canonical paymaster and guarantor instances subtract pending withdrawals and reserved maximum costs from available balance. A guarantor transaction reserves cost even though a later payer may override it.

## Replacement

- Sequenced EIP-8141 identity is `(sender, nonce_keys, nonce_seq)`.
- Nonceless EIP-8141 identity is `(sender, replay_id)`.
- Replacements must independently validate, satisfy fee-bump policy, and move payer reservation atomically.

Disjoint EIP-8141 key sets do not by themselves justify unbounded concurrency because sender and payer balances can still invalidate many pending transactions at once.

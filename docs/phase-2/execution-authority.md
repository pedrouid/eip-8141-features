# Execution Authority for EIP-8141

```
Status:             research draft
Phase:              2 (prerequisite)
Alternative ID:     P2 prerequisite
Depends on:         EIP-8141
Introduces:         execution_authority tx-scoped state, generalised APPROVE(execution)
Shared appendices:  sighash-binding, mempool-tiers
```

## 1. Status and scope

Phase-2 primitive. Hard prerequisite for the permissions proposal ([`phase-2/permissions.md`](permissions.md)). Explicitly out of scope for any Phase-1 alternative: the SENDER-frame `msg.sender` rule change is a core-invariant change and belongs in a later upgrade. Intended to ship as a small standalone EIP because the primitive is useful beyond delegation (multi-sig, account migration, recovery).

## 2. Motivation

Current EIP-8141 is single-authority: the account that signed the tx is the only account whose authority can be used for SENDER execution. Delegated permissions require a model where a delegate signs and submits (so `tx.sender = delegate`) but SENDER frames execute with the delegator's authority. EIP-8141 today does not support this. `execution_authority` is one tx-scoped variable that closes the gap.

## 3. Priorities and non-goals

Priorities:

1. Smallest possible change: one tx-scoped variable, one APPROVE-rule generalisation.
2. Account consent preserved: only the target's own VERIFY frame can set its authority.
3. Standalone EIP, useful beyond delegation.
4. No new opcodes, precompiles, frame types.

Non-goals:

- Bundling with permissions in the same EIP.
- Multi-authority per tx (one execution authority).
- Cross-account nonce writes.

## 4. Single-line spec delta

Introduce `execution_authority: Optional[address]` (initially null). Generalise the `APPROVE(execution)` rule so that, in a VERIFY frame targeting any account X, it sets `execution_authority = X`. SENDER frames execute with `msg.sender = execution_authority ?? tx.sender`.

## 5. Normative spec

### Tx-scoped state (MUST)

`execution_authority: Optional[address]` initialised to null at tx entry.

### Generalised APPROVE(execution) rule (MUST)

- A VERIFY frame whose `frame.target == X` calling `APPROVE(execution)` MUST set `execution_authority = X`.
- A second call to `APPROVE(execution)` in the same tx MUST revert (first-wins).
- `execution_authority` MUST NOT be overridable by calldata. The value is transaction-scoped protocol state, not a frame argument.

### SENDER `msg.sender` rule (MUST)

In SENDER frames, `msg.sender = execution_authority ?? tx.sender`. If `execution_authority` is never set, behavior is byte-identical to today. The legacy `sender_approved` boolean derives as `execution_authority == tx.sender`, or can be removed entirely.

### Nonce consumption (MUST)

- `tx.sender` has its nonce consumed by the protocol as today.
- `execution_authority` MUST NOT have its tx-level nonce consumed. Delegation-layer replay is tracked separately by whatever authorised the delegation (typically manager state via salt/nonce/expiry).

_Rationale:_ keeps the tx-level nonce model single-writer. Alice delegating to Bob does not consume Alice's tx nonce; if Bob redeems 100 times, Alice's nonce doesn't move.

### State access (MUST)

A tx where `execution_authority != tx.sender` reads and writes state for two accounts: `tx.sender`'s nonce, and `execution_authority`'s account state during SENDER-frame execution. Mempool state-access profiles, fee estimation, warm/cold access costs, and access-list pre-computation MUST include both. No new consensus object; access-list computation changes.

### Safety invariants (MUST)

1. Account consent preserved. X cannot become execution authority without a VERIFY frame targeting X, which runs X's code and decides whether to approve.
2. No silent impersonation. A delegate cannot claim execution authority without presenting proof the delegator's code accepts.
3. No double-spending. Only `tx.sender`'s nonce is consumed at the protocol layer.
4. No cross-account nonce writes during tx execution.

## 6. Mempool behavior

Tier semantics in [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md).

### Consensus-relevant (MUST)

- **State-access scope:** a tx where `execution_authority != tx.sender` reads and writes state for two accounts; access-list / fee-estimation rules MUST include both (also §5).

### Node policy (SHOULD)

- **Restrictive-tier admission:** depends on the calling default code's surface (manager-call profile in the permissions case). When the surface exceeds the restrictive budget, route to expansive tier.

## 7. RPC and wallet surface

No new RPC method introduced by this EIP; access-list and `eth_estimateGas` surface include `execution_authority` when set. Wallets surface "this tx will run as `<execution_authority>`" alongside the signing prompt; sponsored-delegated cases distinguish the three roles (signer, authority, payer).

## 8. Security and DoS analysis

- **Consent.** The first-wins, target-only APPROVE rule prevents a third party from injecting an authority without that account's code consenting.
- **Single-writer.** Only `tx.sender`'s nonce is written by the protocol layer; cross-account nonce manipulation is impossible.
- **State-access budget.** A delegated tx touches two accounts' state in the validation prefix; mempool budgets account for the authority side or route to expansive tier when the surface exceeds the restrictive budget (node policy follow-on of the consensus state-access rule).
- **No new opcode surface.** Reuses `APPROVE`; no new frame types.

## 9. Compatibility and interactions

- **Phase-1 alternatives:** untouched. SENDER-frame `msg.sender` rule is unchanged in Phase 1; `execution_authority` is null when this EIP has not shipped.
- **2D nonces:** unaffected. Operates on `tx.sender`'s streams regardless of execution authority.
- **Phase-2 permissions:** this EIP is a hard prerequisite; the delegation flow is `execution_authority = delegator` set by a VERIFY frame targeting the delegator.
- **Three-role transactions:** `tx.sender = delegate`, `execution_authority = delegator`, `payer = sponsor`. No new frame types or opcodes.

### Worked example

Bob has a delegation from Alice; a sponsor pays gas:

| # | Mode | Target | What |
|---|---|---|---|
| 0 | VERIFY | Alice | Default code calls `manager.isAuthorized(...)`; manager verifies via `Alice.validateAuth(...)` and runs caveats. On success default code calls `APPROVE(execution)`. Protocol sets `execution_authority = Alice`. |
| 1 | VERIFY | Sponsor | Sponsor's default code verifies terms, calls `APPROVE(payment)`. |
| 2 | SENDER | USDC | `msg.sender = Alice`. `transfer(Bob, 10 USDC)` from Alice's balance. |

Result: `tx.sender = Bob` (nonce consumed); `execution_authority = Alice` (balance moves); payer = Sponsor; Alice's tx nonce untouched.

## 10. Open questions

None block this proposal. Q9 (placement) resolved: standalone EIP.

## 11. Appendix references

- [`appendix/sighash-binding.md`](../appendix/sighash-binding.md) for Class A/B reasoning if delegation bundles are eventually layered (Class B applies).
- [`appendix/mempool-tiers.md`](../appendix/mempool-tiers.md) for tier semantics.

## 12. Spec delta summary

1. Add tx-scoped state `execution_authority: Optional[address]`, initially null.
2. Extend `APPROVE(execution)` rule: in a VERIFY frame targeting account X, sets `execution_authority = X`. Reverts if already set.
3. SENDER-frame `msg.sender` rule: `execution_authority ?? tx.sender`.
4. Derive `sender_approved := (execution_authority == tx.sender)` or remove it.
5. Access-list / mempool state-access rules: include `execution_authority` account when set.
6. No change to nonce, payment, or signature mechanics.

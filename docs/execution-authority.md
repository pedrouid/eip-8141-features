# EIP-8141 Primitive: Execution Authority

*Author: Claude. Scratch doc, not indexed on the site. Prerequisite for the permissions proposal.*

## Problem

Current EIP-8141 has:

- `tx.sender` — address that signed the outer tx.
- `sender_approved` — boolean, set when a VERIFY frame targeting `tx.sender` calls `APPROVE(execution)`.
- SENDER frames execute with `msg.sender = tx.sender`.

This is a **single-authority model**: the account that signed the tx is the only account whose authority can be used for SENDER execution.

The permissions proposal requires a **delegated-authority model**: the delegate signs and submits the tx (so `tx.sender = delegate`), but SENDER frames should execute with the delegator's authority. Current 8141 does not support this — there is no way to approve execution for an account other than `tx.sender`.

My previous permissions proposal hand-waved this as "existing frame mechanics," which was wrong. Implementable delegation requires a generalization of the current execution-approval mechanism.

---

## Design: `execution_authority` as tx-scoped state

### Generalization, not replacement

Introduce a new tx-scoped variable:

```
execution_authority: Optional[address]  (initially null)
```

Generalize the `APPROVE(execution)` rule:

```
Current: APPROVE(execution) called inside a VERIFY frame targeting tx.sender
         → sets sender_approved = true.

New:     APPROVE(execution) called inside a VERIFY frame targeting any account X
         → sets execution_authority = X.
```

SENDER frames execute with:

```
msg.sender = execution_authority ?? tx.sender
```

If `execution_authority` is never set, behavior is identical to today. `sender_approved` becomes the special case `execution_authority == tx.sender`.

### Invariants

1. **Only one execution authority per transaction.** `APPROVE(execution)` can only set `execution_authority` once; a second call reverts. (Alternative: last-wins. Picking first-wins to keep the mental model simpler.)
2. **Must be set by the target's own VERIFY frame.** Only a VERIFY frame whose `target == X` can set `execution_authority = X`. This enforces account consent: X's own code (default or custom) decides whether to approve.
3. **Cannot be overridden by calldata.** The value is transaction-scoped protocol state, not a frame argument.
4. **Does not affect payment.** `payer_approved` remains tied to whoever pays gas. Execution and payment authorities are orthogonal.

### Relation to existing `sender_approved`

Keep `sender_approved` as a convenience flag or remove it; both are workable. Cleaner to express it as a derived read:

```
sender_approved := (execution_authority == tx.sender)
```

This removes a piece of state without changing semantics.

---

## Nonce consumption

The critical design question the reviewer raised: **whose nonce is consumed?**

- **`tx.sender`** has its nonce consumed by the protocol as today. The delegate signs the tx, pays gas, and increments their own sequence.
- **`execution_authority`** does **not** have its tx-level nonce consumed. Its "delegation redemption" counter is tracked separately by whatever authorized the delegation (the manager's state, via the delegation's own salt/nonce/expiry).

Consequence: Alice delegating to Bob does not consume Alice's tx nonce. If Bob redeems 100 times, Alice's account nonce doesn't move. Alice's delegation counter (inside the manager contract) is what prevents replay at the delegation layer.

This keeps the tx-level nonce model clean: one tx-level nonce, consumed by `tx.sender`. No cross-account nonce writes at the consensus layer.

---

## State access implications

A tx where `execution_authority != tx.sender` reads and writes state for two accounts:

- `tx.sender`'s nonce (as today).
- `execution_authority`'s account state (when SENDER frames execute).

For the mempool, this means a tx's state-access profile now covers two accounts' storage, not one. Fee estimation, warm/cold access costs, and access-list pre-computation must account for both.

For block builders, the same applies. No new consensus object, but the implicit access-list computation changes.

---

## Payment authority remains separate

`execution_authority` is orthogonal to payment. A fully delegated + sponsored tx can have:

- `tx.sender` = delegate (submits, signs)
- `execution_authority` = delegator (SENDER frames run as)
- payer = sponsor (approved via a separate VERIFY frame calling `APPROVE(payment)`)

Three distinct roles, three distinct approval paths. None require new frame types — they all use the existing `APPROVE` opcode with different scopes, evaluated in VERIFY frames targeting each respective account.

---

## Worked example

Bob has a delegation from Alice (10 USDC/day). A sponsor pays gas. Bob submits:

| Frame | Mode | Target | What the frame does |
|---|---|---|---|
| 0 | VERIFY | Alice | Default code calls `manager.isAuthorized(...)`. Manager calls `Alice.validateAuth(delegationDigest, proof)`, runs caveats against the SENDER frames in this tx, returns true. Default code calls `APPROVE(execution)`. Protocol sets `execution_authority = Alice`. |
| 1 | VERIFY | Sponsor | Sponsor's default code verifies the sponsorship terms, calls `APPROVE(payment)`. Protocol sets `payer_approved = true` with payer = Sponsor. |
| 2 | SENDER | USDC | Executes with `msg.sender = execution_authority = Alice`. Calls `transfer(Bob, 10 USDC)` from Alice's balance. |

Properties:

- `tx.sender == Bob` (signed + nonce consumed).
- `execution_authority == Alice` (SENDER frame runs as Alice, Alice's balance moves).
- payer == Sponsor (gas paid from Sponsor's balance).
- Alice's nonce: untouched at tx level. Her delegation's replay counter inside the manager advances.

No new frame types. No new opcodes. One new tx-scoped variable.

---

## Safety properties

1. **Account consent is preserved.** X cannot become execution authority without a VERIFY frame targeting X, which runs X's code (default or custom), which decides whether to approve. Invariant 2 above.
2. **No silent impersonation.** A delegate cannot claim execution authority without presenting proof that the delegator's code accepts.
3. **No double-spending of nonces.** Only `tx.sender`'s nonce is consumed at the protocol layer. Delegation-layer replay is handled separately.
4. **No cross-account nonce writes during tx execution.** Consensus state model stays single-writer per tx-level field.

---

## Spec delta

1. Add tx-scoped state `execution_authority: Optional[address]`, initially null.
2. Extend `APPROVE(execution)` rule: in a VERIFY frame targeting account X, sets `execution_authority = X`. Reverts if already set.
3. SENDER frame `msg.sender` rule: `execution_authority ?? tx.sender`.
4. Derive `sender_approved := (execution_authority == tx.sender)`, or remove `sender_approved` entirely.
5. Access-list / mempool state-access rules: include `execution_authority` account when set.
6. No change to nonce, payment, or signature mechanics.

---

## Impact on the proposals

- **Permissions proposal**: now implementable. The flow "Bob submits tx, SENDER frames run as Alice" is exactly `execution_authority = Alice` set by a VERIFY frame targeting Alice. The manager.isAuthorized call is what gates Alice's default code calling APPROVE(execution). No other frame-model changes needed.
- **2D nonces proposal**: unaffected. 2D nonces operate on `tx.sender`'s streams regardless of who the execution authority is. The delegate's stream consumption and the execution authority's delegation counter are separate layers.

Execution authority and 2D nonces are orthogonal primitives. Both are prerequisites for a clean permissions spec; both are clean in isolation.

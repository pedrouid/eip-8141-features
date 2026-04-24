# EIP-8141 Primitive: Execution Authority

_Author: Claude. Scratch doc, not indexed on the site. Prerequisite for the permissions proposal._

## Problem

Current EIP-8141 has `tx.sender`, `sender_approved` (boolean set when a VERIFY frame targeting `tx.sender` calls `APPROVE(execution)`), and SENDER frames executing with `msg.sender = tx.sender`. This is a single-authority model: the account that signed the tx is the only account whose authority can be used for SENDER execution.

The permissions proposal requires a delegated-authority model where the delegate signs and submits (so `tx.sender = delegate`) but SENDER frames execute with the delegator's authority. Current 8141 does not support this.

## Design: `execution_authority` as tx-scoped state

Introduce `execution_authority: Optional[address]` (initially null). Generalize the `APPROVE(execution)` rule:

- Current: `APPROVE(execution)` called in a VERIFY frame targeting `tx.sender` → sets `sender_approved = true`.
- New: `APPROVE(execution)` called in a VERIFY frame targeting any account X → sets `execution_authority = X`.

SENDER frames execute with `msg.sender = execution_authority ?? tx.sender`. If `execution_authority` is never set, behavior is identical to today; `sender_approved` becomes the derived special case `execution_authority == tx.sender`.

### Invariants

1. **One execution authority per tx.** Second call to `APPROVE(execution)` reverts. First-wins.
2. **Must be set by the target's own VERIFY frame.** Only a VERIFY frame whose `target == X` can set `execution_authority = X`. Enforces account consent.
3. **Cannot be overridden by calldata.** Value is transaction-scoped protocol state, not a frame argument.
4. **Orthogonal to payment.** `payer_approved` stays tied to whoever pays gas.

## Nonce consumption

- `tx.sender` has its nonce consumed by the protocol as today.
- `execution_authority` does not have its tx-level nonce consumed. Delegation-layer replay is tracked separately by whatever authorized the delegation (typically manager state via salt/nonce/expiry).

Alice delegating to Bob does not consume Alice's tx nonce. If Bob redeems 100 times, Alice's account nonce doesn't move. This keeps the tx-level nonce model single-writer.

## State access

A tx where `execution_authority != tx.sender` reads and writes state for two accounts: `tx.sender`'s nonce, and `execution_authority`'s account state during SENDER frame execution. Mempool state-access profiles, fee estimation, warm/cold access costs, and access-list pre-computation must include both. No new consensus object; access-list computation changes.

## Three-role transactions

A fully delegated + sponsored tx has three distinct roles, each approved via the existing `APPROVE` opcode with a different scope in a VERIFY frame targeting that respective account:

- `tx.sender` = delegate (submits, signs).
- `execution_authority` = delegator (SENDER frames run as).
- payer = sponsor (approved via `APPROVE(payment)`).

No new frame types. No new opcodes. One new tx-scoped variable.

## Worked example

Bob has a delegation from Alice; a sponsor pays gas:

| # | Mode | Target | What |
|---|---|---|---|
| 0 | VERIFY | Alice | Default code calls `manager.isAuthorized(...)`; manager verifies via `Alice.validateAuth(...)` and runs caveats. On success default code calls `APPROVE(execution)`. Protocol sets `execution_authority = Alice`. |
| 1 | VERIFY | Sponsor | Sponsor's default code verifies terms, calls `APPROVE(payment)`. |
| 2 | SENDER | USDC | `msg.sender = Alice`. `transfer(Bob, 10 USDC)` from Alice's balance. |

Properties: `tx.sender = Bob` (nonce consumed); `execution_authority = Alice` (balance moves); payer = Sponsor; Alice's tx nonce untouched.

## Safety properties

1. **Account consent preserved.** X cannot become execution authority without a VERIFY frame targeting X, which runs X's code and decides whether to approve.
2. **No silent impersonation.** A delegate cannot claim execution authority without presenting proof the delegator's code accepts.
3. **No double-spending.** Only `tx.sender`'s nonce is consumed at the protocol layer.
4. **No cross-account nonce writes** during tx execution. Consensus state model stays single-writer per tx-level field.

## Spec delta

1. Add tx-scoped state `execution_authority: Optional[address]`, initially null.
2. Extend `APPROVE(execution)` rule: in a VERIFY frame targeting account X, sets `execution_authority = X`. Reverts if already set.
3. SENDER frame `msg.sender` rule: `execution_authority ?? tx.sender`.
4. Derive `sender_approved := (execution_authority == tx.sender)`, or remove `sender_approved` entirely.
5. Access-list / mempool state-access rules: include `execution_authority` account when set.
6. No change to nonce, payment, or signature mechanics.

## Impact on the proposals

- **Permissions**: now implementable. The flow "Bob submits tx, SENDER frames run as Alice" is `execution_authority = Alice` set by a VERIFY frame targeting Alice.
- **2D nonces**: unaffected. Operates on `tx.sender`'s streams regardless of execution authority.

Execution authority and 2D nonces are orthogonal primitives; both are prerequisites for a clean permissions spec; both are clean in isolation.

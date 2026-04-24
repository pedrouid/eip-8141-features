# Summary — Minimal-Scope AA Fork with a Permissions Follow-On

_Author: Claude. Scratch doc, not indexed on the site._

The recommended shape for EIP-8141's first successful landing is a **minimal-scope AA fork** covering three features that together deliver the bulk of user-visible UX improvement, followed by a dedicated **permissions fork** once `execution_authority` is established.

## Base AA fork

Three features alongside base EIP-8141:

1. **Guarantors** (PR #11555). One new `APPROVE(guarantee)` scope, one tx-scoped `guarantor` field, one mempool-admission relaxation. Unlocks ERC-20 paymasters and shared-state caveats via economic risk.
2. **2D nonces**. One new envelope field `nonce_key: uint256`. One system contract (`NonceLaneRegistry`) at a reserved address, following the EIP-4788 / EIP-2935 precedent. Lane state lives in ordinary contract storage — no account-encoding changes, no new witness types. Solves the "one stuck transaction blocks my account" problem for every EOA.
3. **Validity windows**. Two envelope fields (`valid_after`, `valid_before`), one pre-tx consensus check. No state, no contracts. Solves stale-signature attacks at the public-mempool level.

Net protocol surface: **3 envelope fields, 1 system contract, 1 new APPROVE scope, 2 tx-scoped fields, 0 opcodes, 0 precompiles, 0 core-invariant changes, 0 account-encoding changes.** Every piece has independent design precedent. Any one can be pulled without invalidating the others.

## Permissions on top

Delegated permissions (ERC-7710 / ERC-7715 style) are deferred to a **v2 fork**. The base fork's three features give wallet devs enough to build ~85 % of the permissions UX in software — session keys as scoped signers on 2D-nonce lanes, dapp allowances via ERC-7710 contracts where `msg.sender = manager` suffices, scheduled payments via native `valid_after`, recovery flows on reserved lanes, guarantor-backed shared-state caveats.

What the base fork cannot cover is the narrow case where `msg.sender` must literally be the delegator inside the SENDER frame. That's the gap a v2 permissions fork closes, built on a dedicated `execution-authority` EIP (generalized `APPROVE(execution)` + tx-scoped `execution_authority` state + SENDER-frame `msg.sender` rule change) and an immutable DelegationManager system contract.

## Why this sequencing

Core-dev feedback, weighted most heavily, supports this split: the base fork contains only changes with independent precedent, no core-invariant changes, manageable cross-client test surface. Wallet-dev feedback confirms nonce blocking + stale signatures + paymaster coverage are the three pain points users actually feel — all three ship in the base fork. Permissions take time to design correctly; users don't wait for them.

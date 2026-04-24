# Summary — Minimal-Scope AA Fork with a Permissions Follow-On

_Scratch doc, not indexed on the site._

The recommended shape for EIP-8141's first successful landing is a minimal-scope AA fork with three features, followed by a dedicated permissions fork once `execution_authority` is established.

## Base AA fork

1. **Guarantors** (PR #11555). One `APPROVE(guarantee)` scope, one tx-scoped `guarantor` field, one mempool relaxation. Unlocks ERC-20 paymasters and shared-state caveats via economic risk.
2. **2D nonces**. Envelope field `nonce_key: uint256`. System contract `NonceLaneRegistry` at a reserved address (EIP-4788 / EIP-2935 pattern). Lane state is ordinary contract storage — no account-encoding changes. Solves the stuck-tx problem for every EOA.
3. **Validity windows**. Envelope fields `valid_after` and `valid_before`, one pre-tx consensus check. No state, no contracts. Solves stale-signature attacks.

Net: 3 envelope fields, 1 system contract, 1 APPROVE scope, 2 tx-scoped fields, 0 opcodes, 0 precompiles, 0 core-invariant changes, 0 account-encoding changes. Every piece has independent precedent; any one can be pulled without invalidating the others.

## Permissions on top

Delegated permissions defer to a v2 fork. The base fork's primitives let wallet devs build ~85 % of the permissions UX in software: session keys as scoped signers on 2D-nonce lanes, dapp allowances via ERC-7710 contracts where `msg.sender = manager` suffices, scheduled payments via `valid_after`, guarantor-backed shared-state caveats.

The base fork cannot cover the case where `msg.sender` must literally be the delegator. That closes in a v2 permissions fork built on a standalone `execution-authority` EIP plus an immutable DelegationManager contract.

## Why this sequencing

Core-dev feedback supports the split: base fork has only changes with independent precedent, no core-invariant changes, manageable cross-client test surface. Wallet-dev feedback confirms nonce blocking, stale signatures, and paymaster coverage are the pain points users feel. Permissions take time; users don't wait.

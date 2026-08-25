# EIP-8141 Upgrade

Research and a rebased EIP-shaped draft for extending [EIP-8141](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8141.md) without replacing the protocol surfaces it has gained upstream.

## Current position

The project preserves four outcomes:

1. **Arbitrary validation through the public mempool.** Guarantors pay even when sender validation fails. The mechanism is rebased from the closed, stale [guarantors PR #11555](https://github.com/ethereum/EIPs/pull/11555) onto the current signature-list and two-dimensional-gas design.
2. **Parallel replay domains.** EIP-8141 directly carries ordered nonce-key sets and protocol-managed sequences, using the stronger design developed in [EIP-8250](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-8250.md) instead of the old single `signer` envelope fork.
3. **Compatibility for non-secp256k1 accounts.** Signer-binding `VERIFY` frames let account code bind application digests to an address for transaction-scoped `ECRECOVER` compatibility. They use EIP-8141's `signatures`, `SIGPARAM`, and `SIGDATACOPY`; no pubkey registry is required.
4. **Counter-free replay protection.** EIP-8130's nonceless pattern is integrated into EIP-8141 as `[NONCE_KEY_MAX]`: short mandatory expiry, a fee- and signature-invariant replay identifier, and bounded consensus replay state. The two coupled L1 activation values remain to be benchmarked.

## Canonical artifacts

- [`EIPS/eip-8141.md`](EIPS/eip-8141.md): current upstream EIP-8141 plus native sequenced and nonceless nonce modes, guarantors, and return-data signer binding.
- [`EIPS/eip-8141.diff`](EIPS/eip-8141.diff): exact delta against current upstream.
- [`assets/eip-8141/CanonicalPaymaster.sol`](assets/eip-8141/CanonicalPaymaster.sol): canonical paymaster with payment and guarantor modes.
- [`docs/compare.md`](docs/compare.md): old mechanism to current mechanism migration map.
- [`docs/summary.md`](docs/summary.md): upstream PR-shaped summary.

## Proposal set

| Proposal | Role |
|---|---|
| [`flexible-nonces`](docs/proposals/flexible-nonces.md) | Native EIP-8141 nonce key sets |
| [`signer-binding`](docs/proposals/signer-binding.md) | Transaction-scoped `ECRECOVER` compatibility |
| [`key-streams`](docs/proposals/key-streams.md) | Native keyed nonces plus signer binding |
| [`nonceless-transactions`](docs/proposals/nonceless-transactions.md) | EIP-8130-derived nonce-free replay mode |
| [`auth-scopes`](docs/proposals/auth-scopes.md) | Maximum bundle comparison |
| [`envelope-expiry`](docs/proposals/envelope-expiry.md) | Historical comparison, superseded by expiry verifier |
| [`validity-windows`](docs/proposals/validity-windows.md) | Historical comparison, only `valid_after` remains distinct |

## Rebase baseline

The draft is rebased on `ethereum/EIPs` commit `15bc93fd63181f6d1af31e9a93f33f922d13286b`, with EIP-8141 changes through August 24, 2026. Upstream text is preserved except where the four canonical additions require a direct change.

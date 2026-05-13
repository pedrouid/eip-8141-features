# One Contract, Two Envelope Fields, Four Features

_Why EIP-8141 should land all four upgrades as a single bundle._

EIP-8141 is the one realistic chance to lift account abstraction into the protocol layer. The PR at [ethereum/EIPs#11643](https://github.com/ethereum/EIPs/pull/11643) bundles four additions: **guarantors**, **flexible nonces**, **signer binding**, and **envelope expiry**. The first three are not independent. Splitting them costs more code, not less.

**Guarantors and flexible nonces.** A guarantor commits to paying gas even when sender VERIFY fails. To stay replay-safe, the sender's nonce must advance on inclusion regardless of validation outcome. The legacy account-nonce model fights this. Flexible nonces give it natively: per-signer streams that consume one slot per included transaction, success or failure. One feature unlocks the other.

**Flexible nonces and signer binding.** Both require protocol-managed state per sender, keyed by an identifier into a system contract. Standalone, that is two reserved addresses, two code hashes, two RPC roots. Bundled, it is one `AuthManager` holding both nonce streams and registered pubkey signers, indexed by the same `(account, signer)` tuple. Half the state surface, half the upgrade cost.

**Signer binding and guarantors.** Both depend on the mempool admitting transactions without simulating sender VERIFY. Together they give post-quantum accounts a credible path to the public mempool. Apart, the admission story has to be re-argued twice.

**Envelope expiry** is a separate concern with a tiny surface: one `uint64` field, no system contract, no per-account state. It lifts the offchain deadline used by every intent, swap, and settlement flow into a consensus-enforced field, removing filler timing as a trust assumption. Zero per-tx state beyond the envelope itself; it composes cleanly with the statelessness roadmap.

---

**Learn the background.** The history and evolution of EIP-8141, and what the current spec can already do today: [eip8141.io](https://eip8141.io).

**Review the PR.** Wallet teams, paymaster authors, and post-quantum implementers especially: feedback while the spec is open is what determines what ships. [ethereum/EIPs#11643](https://github.com/ethereum/EIPs/pull/11643).

# 1 Contract, 1 Field, 3 Features

_Why EIP-8141 should land the remaining three upgrades as a single bundle._

EIP-8141 is the one realistic chance to ship account abstraction into the protocol layer. The previous PR ([ethereum/EIPs#11643](https://github.com/ethereum/EIPs/pull/11643)) bundled four additions: **guarantors**, **flexible nonces**, **signer binding**, and **envelope expiry**. Upstream has since merged an in-spec **expiry verifier frame** at `EXPIRY_VERIFIER = address(0x8141)` that handles deadlines as the 8-byte `frame.data` of a special `VERIFY` frame, covered by `compute_sig_hash` and dropped deterministically from the public mempool when expired. That merged change subsumes envelope expiry, so the new PR drops the field and ships the remaining three additions. The features could be independent. Splitting them costs more code, not less.

**Guarantors and flexible nonces**
A guarantor commits to paying gas even when sender VERIFY fails. To stay replay-safe, the sender's nonce must advance on inclusion regardless of validation outcome. The legacy account-nonce model fights this. Flexible nonces give it natively: per-signer streams that consume one slot per included transaction, success or failure. One feature unlocks the other.

**Flexible nonces and signer binding**
Both require protocol-managed state per sender, keyed by an identifier into a system contract. Standalone, that is two reserved addresses, two code hashes, two RPC roots. Bundled, it is one `AuthManager` holding both nonce streams and registered pubkey signers, indexed by the same `(account, signer)` tuple. Half the state surface, half the upgrade cost.

**Signer binding and guarantors**
Both depend on the mempool admitting transactions without simulating sender VERIFY. Together they give post-quantum accounts a credible path to the public mempool. Split apart, each has to win the same mempool argument on its own.

**Deadlines, already merged**
The upstream expiry verifier frame is the canonical deadline mechanism: one envelope-cost-free byte of `frame.data` per tx that opts in, zero per-tx cost for everything else. It composes cleanly with the statelessness roadmap and with each of the three additions above, with no envelope changes from this proposal.

**Learn the background:** The history and evolution of EIP-8141, deep-dive into AA topics and what the current spec can already do today -> [eip8141.io](https://eip8141.io).

**Review the PR:** Jump into the new PR and participate in the discussion and give feedback to determine what ships for native AA -> [ethereum/EIPs#11643](https://github.com/ethereum/EIPs/pull/11643).

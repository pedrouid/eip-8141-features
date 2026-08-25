# System State

## EIP-8141 `NONCE_MANAGER`

The consolidated EIP-8141 draft defines:

- the `NONCE_MANAGER` address and activation;
- full-width nonce-key slot derivation;
- nonce-set validation and atomic advancement;
- first-use pricing;
- transaction introspection and mempool identity.

The mechanics derive from EIP-8250, but EIP-8141 is the normative owner. The design deliberately does not narrow the surface to one signer-coupled stream.

## Signer binding

Signer binding requires no persistent protocol contract. Account code validates signature entries or arbitrary witnesses during a `VERIFY` frame and returns application digests. The protocol stores only a transaction-scoped map, discarded after execution.

Accounts that want persistent public-key aliases may use the future extension sketched by current EIP-8141. That mechanism is outside this proposal and should not be preempted by a second registry.

## Canonical paymaster

`CanonicalPaymaster.sol` is an ordinary deployable contract recognized by exact runtime-code match in the public mempool. It stores:

- one owner address;
- delayed-withdrawal state;
- `guarantor_nonce[sender]` replay counters.

The paymaster is not a protocol system contract. Its runtime identity is a mempool policy anchor.

## Nonceless replay state

The consolidated draft installs `NONCELESS_REPLAY_MANAGER` as a separate EIP-8141 system account. Domain-separated storage holds:

- the next circular-ring index;
- two packed slots per ring entry; and
- one live-map slot per `(sender, replay_id)`.

Separating it from `NONCE_MANAGER` prevents slot-layout collisions and keeps the nonceless capacity resource explicit. Ordinary calls revert. Protocol insertion occurs only during sender-authorized payment approval, uses the approving frame's EIP-8037 state gas, and can create at most four storage slots (`391,680` state gas). The state rolls back normally on reorgs.

## Removed `AuthManager`

The old contract combined signer pubkeys and nonce streams. It is removed because:

- EIP-8141 now owns a richer nonce-set design derived from EIP-8250;
- current EIP-8141 already exposes signature metadata and custom witness bytes;
- account code, not a protocol registry, is the correct binding authority;
- permanent storage of large public keys is avoidable.

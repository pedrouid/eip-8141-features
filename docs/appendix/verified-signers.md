# Verified Signers

## Table

Each frame transaction initializes:

```text
verified_signers: map[bytes32 digest -> address account]
```

The table is transaction-scoped, capped at `MAX_BOUND_SIGNERS = 8`, and discarded after settlement.

## Population

A frame may populate the table only when:

1. `frame.mode == VERIFY`;
2. `frame.flags == SIGNER_BINDING_FLAG`;
3. `frame.target` is explicit and non-null;
4. the frame succeeds under normal `VERIFY` restrictions;
5. return data is a non-empty multiple of 32 bytes.

Each 32-byte return word is a digest bound to `frame.target`. Re-inserting the same pair is a no-op. Binding an existing digest to another target reverts. Exceeding the cap reverts.

The account code decides how authorization is proven. It may inspect protocol-validated signature metadata through `SIGPARAM`, copy an `ARBITRARY` witness through `SIGDATACOPY`, and apply account storage or delegation policy. No registry lookup is implied by the protocol.

## `ECRECOVER`

```python
def ECRECOVER(digest, v, r, s):
    if digest in verified_signers:
        return verified_signers[digest]
    return existing_secp256k1_recover(digest, v, r, s)
```

The hit ignores `v`, `r`, and `s`. The miss path is unchanged. The existing precompile gas cost applies to both.

## Frame isolation

A binding frame cannot approve execution, payment, or guarantee scope. Its failure is never covered by the guarantor sender-validation exception. The table changes are transaction context, not persistent state, and revert with the binding frame.

## Wallet requirement

A wallet must show the account being bound, each application digest, and the downstream action that will consume the binding. A canonical transaction signature alone is not evidence that the account intended an arbitrary application digest.

# Spec: dual-root State + per-leaf owner-sig at Modify

!!! warning "Superseded current-auth resolution: `identity_root` inclusion + `cur_pubkey` digest here is the rejected Candidate-B lineage (#92)"
    Per `specs/92-checkpoint-contention/DECISION.md`, the **current-authority resolution** of
    this spec — the cage snapshotting `identity_root` and proving `identity_root[owner_aid] =
    blake2b_256(cur_pubkey)` against a single/shared MPF identity registry, with `OwnerAuth`
    supplying an inclusion proof into that shared root — is the **rejected Candidate-B legacy**.
    The #92 sovereign per-AID decision (Candidate A) re-cuts current-actor resolution: the cage
    resolves an AID's current authority by reading that AID's **own sovereign, per-AID,
    quantity-one uniquely-tokenized checkpoint UTxO** — asset id `(checkpoint_policy_id,
    aid_asset_name)`, current weighted keys/threshold in the inline `CheckpointDatum` — as a
    **CIP-31 reference input**, discovered by a **generic exact-asset `(policy_id, asset_name)`
    lookup** (candidate outref for liveness only, re-validated against the ledger). A `delta =
    0` rotation (`seq + 1`) **consumes** the referenced checkpoint UTxO, so a pending
    value-write authorization is **stale** and cannot merely be re-pointed at the fresh
    checkpoint: it MUST be **discarded and re-signed** by the AID's **current weighted keys**
    over the fully bound write + current sequence (value-bearing flows carry the explicit
    **Execute / Refresh-Re-sign / Cancel-Reclaim / Expire-Cleanup** lifecycle) — there is no
    shared `root_window` freshness floor. Lifecycle (close) and freeze are **not** fields of
    the `CheckpointDatum` (which carries only the AID/sequence binding + current weighted key
    state): close is the checkpoint's **mint/spend lineage** and freeze is the **separate,
    shared, attacker-contendable R-FRZ** registry. The **mechanical re-cut of `cage.ak` /
    `OwnerAuth` is downstream
    #23** — not performed in this document. **Unchanged**: that the **oracle alone cannot
    authorize a write to an AID-owned leaf** (a **witness set meeting the checkpoint's current
    weighted threshold** over the fully bound write + current sequence is still required, not a
    single current-key signature) — only the surface that *resolves* the current keys moves
    from a shared registry root to the AID's sovereign checkpoint.

Issue: https://github.com/lambdasistemi/cardano-keri/issues/23
Epic: https://github.com/lambdasistemi/cardano-keri/issues/21

## Problem

The upstream cage validator allows the oracle to write any value to any leaf.
For AID-owned leaves the oracle must be cryptographically excluded from `Modify`:
a valid Ed25519 signature from the AID's current key must be required alongside
the oracle signature. Oracle remains necessary (liveness/ordering) but is no
longer sufficient.

## Scope

cardano-keri writes its own cage validator (`validators/cage.ak`) extending the
mpfs-onchain pattern. Since mpfs-onchain's Aiken code lives in `validators/`
(not importable as a package), the relevant files are copied and extended:

- `validators/types.ak` — types with `State` and `RequestAction` extended
- `validators/lib.ak` — verbatim copy of mpfs-onchain lib.ak helpers
- `validators/cage.ak` — extended cage with identity auth in `mkAction`

Add `aiken-lang/merkle-patricia-forestry` as a direct dependency in `aiken.toml`.

## Type Changes

### `State` — breaking datum change

```aiken
pub type State {
  owner: VerificationKeyHash,
  root: ByteArray,
  identity_root: ByteArray,  -- NEW: snapshot of AID identity registry MPF root
  tip: Int,
  process_time: Int,
  retract_time: Int,
}
```

`identity_root` is set at mint and updated by the oracle in the output `Modify`
datum as the identity registry advances.

### `OwnerAuth` — new type

```aiken
pub type OwnerAuth {
  owner_aid: ByteArray   -- key in identity_root trie (AID identifier)
  identity_proof: Proof  -- MPF inclusion: identity_root[owner_aid] = blake2b_256(owner_key)
  owner_key: ByteArray   -- raw Ed25519 public key (32 bytes)
  owner_sig: ByteArray   -- Ed25519 signature (64 bytes)
}
```

### `RequestAction` — breaking change

```aiken
pub type RequestAction {
  UpdateAction { value_proof: Proof, auth: OwnerAuth }  -- was: UpdateAction(Proof)
  Rejected
}
```

## Identity Trie Convention

The AID identity registry MPF maps `owner_aid → blake2b_256(cur_pubkey)`.
Storing the key digest (not raw key) lets the on-chain script verify key
possession via hash-preimage check without exposing the raw key in the trie.

## On-chain Verification per Leaf (inside `mkAction`, `UpdateAction` branch)

1. **Identity inclusion** — verify `identity_root[owner_aid] = blake2b_256(owner_key)`:
   ```aiken
   let id_trie = mpf.from_root(identity_root)
   let cur_key_digest = blake2b_256(owner_key)
   // no-op update: old == new proves inclusion without mutating root
   let _ = mpf.update(id_trie, owner_aid, identity_proof, cur_key_digest, cur_key_digest)
   ```

2. **Owner signature** — verify the owner signed this specific request:
   ```aiken
   let msg = blake2b_256(
     "cardano-keri/value-write/v1"
       |> bytearray.concat(input.output_reference.transaction_id)
       |> bytearray.concat(from_int_big_endian(input.output_reference.output_index, 2))
   )
   expect verify_ed25519(owner_key, msg, owner_sig)
   ```

3. **Value MPF op** — existing logic with `value_proof` (unchanged).

The signed `msg` binds to the request UTxO's output reference (unique per request),
providing replay protection without CBOR encoding overhead.

## Fold Gap Fix

After the `foldl` in `validModify`, assert the remaining actions list is empty:

```aiken
let (expectedNewRoot, remainingActions, owners, totalInputLovelace) = foldl(...)
expect remainingActions == []
```

Prevents silent over-provisioning of actions.

## `validModify` changes

- Threads `identity_root` from `state` into `mkAction`
- Checks output datum `identity_root` is unchanged (oracle cannot silently swap
  the identity snapshot without a deliberate update operation)

## Acceptance Criteria

- Oracle-only Modify on an owned leaf → rejected
- Oracle + valid owner sig → accepted
- Oracle + owner sig over wrong message → rejected
- Oracle + owner sig for wrong AID → rejected
- Redeemer actions list not fully consumed → rejected

## Exec Unit Budget

After implementation, run tests with batches of 1, 5, 10 requests and document
max batch size within PV3 mem+CPU limits.

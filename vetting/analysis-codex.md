# MPFS KERI-AID-owned leaves design analysis

## Executive summary
1. The current validator authorizes `Modify` with only the cage `State.owner` Cardano key hash; per-leaf ownership is not represented in the datum, request datum, or redeemer.
2. Aiken/Plutus V3 gives usable hashes plus single-signature checks such as `verify_ed25519_signature`, but the validator cannot replay a KERI KEL or enforce KERI threshold/recovery semantics.
3. Design A can protect existing leaves if the owner key-state is embedded in each proven leaf value, but it couples value encoding to authorization and makes rotation, migration, and global-key semantics brittle.
4. Design B, a parallel owners MPF committed by a second state root, gives the contract a clean local proof: key -> current owner key-state, then one owner signature over the requested mutation.
5. Recommendation: implement B, with an optional owner digest copied into the value for reader convenience only. Prototype one-request Update/Delete first, then Insert/first-claim, then rotation.

## 1. On-chain enforcement

Current source shape:

- `/code/cardano-mpfs-onchain/validators/types.ak` defines `State { owner, root, tip, process_time, retract_time }`.
- `Request` contains `requestToken`, `requestOwner`, `requestKey`, `requestValue`, `tip`, and `submitted_at`.
- `UpdateRedeemer.Modify(List<RequestAction>)` contains per-request `UpdateAction(Proof)` or `Rejected`.
- `/code/cardano-mpfs-onchain/validators/cage.ak` calls `validateOwnership(state, tx)` before `validModify`; this only checks that the cage owner key hash is in `tx.extra_signatories`.
- `validModify` folds request inputs and calls `mpf.insert`, `mpf.delete`, or `mpf.update` against the single state `root`.
- No current check binds a leaf mutation to the requester or to a leaf owner. The oracle/cage owner can process any request whose MPF proof validates.

The hard constraint is confirmed in the local Aiken stdlib: `aiken/crypto.ak` exposes `verify_ed25519_signature`, `verify_ecdsa_signature`, `verify_schnorr_signature`, and hashes. There is no practical substrate here for KERI CESR parsing, KEL replay, key-event threshold logic, or recovery semantics. The on-chain check must be a single current-key signature over a deterministic MPFS mutation message, with the current key-state itself committed on-chain.

### Design A: owner embedded in the leaf

The only viable A variant is "owner embedded in value", not "owner embedded in key", if MPFS keys are meant to remain global. If the owner is part of the MPF key, then two owners can create two different physical keys for the same logical key, and the contract no longer protects a unique global key.

For owner-in-value, the operation must stop treating the value as an opaque `ByteArray`. The validator has to reconstruct the exact old and new leaf bytes from structured fields so it can both inspect the owner and feed the same bytes into `mpf.update/delete/insert`.

Sketch:

```aiken
pub type OwnerCell {
  aid: ByteArray,
  key_state_digest: ByteArray,
  current_ed25519_vk: ByteArray,
  sequence: Int,
  next_key_digest: ByteArray, // optional simplified pre-rotation hook
}

pub type OwnedLeaf {
  owner: OwnerCell,
  payload: ByteArray,
}

pub type LeafAuth {
  msg_version: Int,
  valid_before: Int,
  nonce: ByteArray,
  signature: ByteArray,
}

pub type OwnedOperation {
  InsertOwned(new_leaf: OwnedLeaf, auth: LeafAuth)
  DeleteOwned(old_leaf: OwnedLeaf, auth: LeafAuth)
  UpdateOwned(old_leaf: OwnedLeaf, new_leaf: OwnedLeaf, auth: LeafAuth)
  RotateOwned(old_leaf: OwnedLeaf, new_leaf: OwnedLeaf, auth: LeafAuth)
}
```

For existing-key Update/Delete, the validator checks:

1. The value proof is valid against the current value root using `encode_owned_leaf(old_leaf)`.
2. The signature verifies against `old_leaf.owner.current_ed25519_vk`.
3. The signed message binds at least: domain separator, validator version, policy id, token id, request key, operation tag, old leaf digest, new leaf digest or tombstone, old owner digest, optional new owner digest, `valid_before`, and nonce.
4. The transaction validity interval is before `valid_before`.
5. The computed new root equals the output datum root.

For Insert, there is no old owner. The validator can only enforce the chosen unowned-key policy: first-claim, oracle-assigned, bonded/challenge, or reserved namespace. With first-claim, any party with any valid current key-state can claim an absent key; that stops forgery of somebody else's existing leaf but does not stop squatting unowned keys.

A's weak point is that the owner key-state is anchored only by being in the value root. That is sufficient by induction for existing leaves, provided the initial state is sound, but it forces every value parser and every reader to understand the owned-leaf envelope.

### Design B: parallel owners MPF

The state datum gets a second root:

```aiken
pub type State {
  owner: VerificationKeyHash,   // oracle/cage operator
  value_root: ByteArray,        // current MPF value root
  owners_root: ByteArray,       // key -> OwnerCell MPF root
  tip: Int,
  process_time: Int,
  retract_time: Int,
}

pub type OwnerCell {
  aid: ByteArray,
  key_state_digest: ByteArray,
  current_ed25519_vk: ByteArray,
  sequence: Int,
  next_key_digest: ByteArray,
}

pub type OwnerAuth {
  owner_cell: OwnerCell,
  owner_proof: Proof,
  new_owner_cell: Option<OwnerCell>,
  new_owner_proof: Option<Proof>,
  msg_version: Int,
  valid_before: Int,
  nonce: ByteArray,
  signature: ByteArray,
}

pub type RequestAction {
  UpdateAction(value_proof: Proof, auth: OwnerAuth)
  Rejected
}
```

For an existing value Update/Delete, the validator checks:

1. The request targets this token and is in the correct time phase, as today.
2. The owner proof proves `requestKey -> encode_owner_cell(owner_cell)` under the current `owners_root`.
3. `verify_ed25519_signature(owner_cell.current_ed25519_vk, mutation_message, signature)` is true.
4. The value proof applies the requested Insert/Delete/Update against the current `value_root`.
5. The owners root is unchanged for ordinary value mutation, or changes exactly according to a rotation/transfer operation.
6. The output datum roots equal the folded `value_root` and `owners_root` accumulators.
7. The cage owner signature is still required to sequence requests, pay refunds, collect tips, and preserve the state UTxO.

The signed mutation message should be a fixed, canonical byte encoding, not ad hoc concatenation without lengths. It should bind:

```text
"mpfs-keri-leaf-v1"
+ policy_id
+ token_id.asset_name
+ request_key
+ operation_tag
+ hash(old_value or empty)
+ hash(new_value or empty)
+ hash(owner_cell)
+ hash(new_owner_cell or empty)
+ valid_before
+ nonce
```

Do not bind the current MPF root unless request creation and proof generation are made atomic. In the current architecture, requests are created before the oracle chooses a later update batch and proof. Binding roots would make ordinary pending requests fragile. The consumed request UTxO plus old-value proof already prevents normal duplicate application; `valid_before` and nonce limit copied signatures.

The current `validModify` ignores leftover `RequestAction`s after the input fold. A v2 validator should tighten this while adding owner auth: either assert no actions remain, or replace input scanning with an explicit list of request refs/actions so the action count is exact and auditable.

## 2. Data structures and proofs

B's datum layout is the cleanest local invariant:

```text
StateDatum(StateV2 {
  owner,
  value_root,
  owners_root,
  tip,
  process_time,
  retract_time
})
```

The owners MPF maps the exact value key bytes to an `OwnerCell` encoding:

```text
owners_mpf[leaf_key] = encode_owner_cell({
  aid,
  key_state_digest,
  current_ed25519_vk,
  sequence,
  next_key_digest
})
```

The value MPF remains unchanged:

```text
value_mpf[leaf_key] = value_bytes
```

Proof composition for one existing-key update:

```text
owners_acc = owners_root_in
value_acc  = value_root_in

owner_proof: prove owners_acc includes key -> owner_cell
sig:         verify owner_cell.current_ed25519_vk signs mutation message
value_proof: prove value_acc includes key -> old_value, then compute new_value

owners_acc unchanged
value_acc  = updated value root
```

Proof composition for first insert:

```text
owner_proof: prove owners_acc excludes key
value_proof: prove value_acc excludes key
sig:         claimant key signs "claim key + insert value"

owners_acc = insert key -> owner_cell
value_acc  = insert key -> new_value
```

Proof composition for delete has a policy choice:

- Keep owner cell after deleting the value. This preserves the reservation and allows the owner to reinsert later.
- Delete both value and owner cell. This releases the key for first-claim again.
- Write an owner tombstone. This gives readers a durable deletion/ownership history marker.

For a global namespace, I recommend keeping the owner cell or writing a tombstone. Deleting the owner mapping makes key theft-by-delete possible if the owner later signs a delete and the oracle or another party first-claims the now-unowned key.

New-key ownership is not solved by cryptography alone. The choices are:

- First-claim: simplest and fully permissionless, but allows squatting by anyone, including the oracle.
- Oracle-assigned reservation: good for curated namespaces, but residual trust remains at allocation time.
- Bonded first-claim plus challenge: more complex; useful if key conflicts are expected.
- Self-certifying keys: require `leaf_key = hash(aid || logical_key)` or similar. This avoids squatting but changes semantics from global keys to owner namespaces.

For the stated goal, B plus first-claim is enough to say "the oracle cannot forge or alter a leaf it does not own" once a key is owned. It is not enough to say "the oracle cannot claim an unowned global key".

## 3. Operation model

Boot:

- Current boot initializes one empty root. V2 boot must initialize both `value_root = root(empty)` and `owners_root = root(empty)`.
- The cage `owner` remains the oracle/operator key that signs state transitions. It is not the leaf owner.

Request Insert:

- Request datum gains `OwnerAuth` or a compact `LeafAuthBody + signature`.
- Proofs should stay in the `Modify` redeemer because proofs depend on the update batch's current/intermediate roots.
- For first-claim insert, the owner proof is an absence proof in the owners MPF and the value proof is an absence proof in the value MPF.

Request Update/Delete:

- The leaf owner signs the operation body. The request UTxO stores the auth body/signature.
- The oracle later includes the request in a `Modify` transaction with both value proof and owner proof.
- The contract requires both: oracle/cage owner signature for the state transition and leaf-owner Ed25519 signature for the leaf mutation.

Reject:

- Reject remains an oracle/cage-owner action over pending request UTxOs.
- It must not require a leaf-owner signature because it does not mutate roots.
- The current phase checks can remain: reject only when request is rejectable, with refunds preserved.

Retract:

- Retract remains request-owner controlled, currently by Cardano payment key hash.
- This is separate from KERI leaf ownership. If those identities should align, the request datum can bind the KERI auth body to `requestOwner`, but Cardano refund control and KERI data control are different concepts.

End:

- Current `End` lets the cage owner burn the token. That remains a residual operator power over the entire cage.
- If the product promise is that leaf owners retain data availability, V2 should restrict End to `value_root == root(empty)` or require an explicit governance/migration path. Otherwise the oracle cannot forge leaves, but it can still destroy the cage.

Garbage collection:

- The oracle can GC/reject stale request UTxOs.
- The oracle must not be able to GC owned value leaves unless the owner signed a delete, the owner cell has an explicit expiry policy that the validator can check locally, or the system accepts curator-delete trust.

## 4. Forgery resistance

Current system:

- The oracle can set any leaf to any value if it can produce a valid MPF proof for the requested operation and sign as cage owner.
- Requesters pay and can retract, but requester identity does not authorize the leaf content.

Design A, owner in value:

- The oracle cannot update/delete an existing well-formed owned leaf unless it has a signature from the old embedded owner key.
- The oracle cannot transfer ownership of an existing leaf unless the old owner signs a value transition to a new owner cell.
- The oracle can still claim unowned keys under first-claim.
- The oracle can exploit malformed or legacy values unless V2 rejects all non-owned leaf encodings after migration.
- If owner is embedded in the key instead of value, the oracle can create alternate physical keys for the same logical key under a different owner; that is not a robust global-key ownership model.

Design B, owners MPF:

- The oracle cannot update/delete an owned value leaf without proving the owner cell from `owners_root` and verifying the owner's signature.
- The oracle cannot change the owner mapping unless the operation explicitly updates `owners_root` under a signed rotation/transfer/claim rule.
- The oracle cannot make the output roots arbitrary because both roots are locally recomputed from input roots and proofs.
- The oracle can still censor requests, choose batch order, collect allowed tips, reject rejectable requests, and possibly end the cage if End remains unrestricted.
- The oracle can still allocate or squat unowned keys if the chosen new-key policy permits first-claim.
- The oracle or a bad anchor publisher can still lie about key-state evolution unless readers verify the off-chain KEL and anchor history.

Residual trust is therefore narrowed from "oracle can forge data" to "oracle controls liveness, ordering, allocation policy for unowned keys, and whole-cage lifecycle".

## 5. Key rotation and compromise

On-chain, rotation must be reduced to a local owner-cell update:

```text
owners_mpf[key] = old_owner_cell
old_owner_cell.current_ed25519_vk signs:
  rotate key from hash(old_owner_cell) to hash(new_owner_cell)
validator verifies old owner proof, signature, and owners-root transition
```

If the old owner cell carries `next_key_digest`, the validator can optionally require `hash(new_owner_cell.current_ed25519_vk) == old_owner_cell.next_key_digest`. This gives a cheap one-step pre-rotation check if the digest function is available on-chain. It is not a KEL replay.

The off-chain KERI verifier must do the real work:

- Replay the AID's KEL from inception to the claimed key-state.
- Verify event signatures, thresholds, next-key commitments, recovery, and duplicity rules.
- Check that the `key_state_digest` and `current_ed25519_vk` in the owner cell match the replayed current state.
- Check that the owner-cell update is anchored in the transaction history at the point the owners root changes.

Compromise is the hard case. If the current key is compromised, the attacker can produce the single signature the chain accepts until a later rotation/recovery is anchored. KERI recovery can let off-chain readers decide a later state supersedes the compromised one, but the chain cannot retroactively know that while validating a single mutation. If the design needs threshold KERI control on-chain, one Ed25519 verify is not enough unless the KERI state is reduced off-chain to a single aggregate or delegated signing key.

## 6. Off-chain pure verifier

The existing verifier architecture is a good fit. `cardano-mpfs-verify` already has pure verification modules, proof-bearing bundles, MPF proof replay, and a cross-target plan for native/WASM/JS byte-identical verdicts. It anchors state UTxOs to a trusted UTxO-CSMT root and replays MPF facts against the state root.

B requires extending the pure verifier to check two independent commitments:

1. The state UTxO is anchored to the trusted UTxO root.
2. The value facts reconstruct to `value_root`.
3. The owner facts reconstruct to `owners_root`.
4. Every value fact has a matching owner fact for the same key, unless it is a tombstone or explicitly unowned under policy.
5. Each owner cell's `aid`, `key_state_digest`, and `current_ed25519_vk` are consistent with an off-chain KEL replay.
6. Each observed mutation transaction that changes a value leaf has the owner proof and signature that the on-chain validator would accept.

The KERI verifier should remain pure and cross-target:

- No networking, filesystem, wall-clock time, or mutable global state in verifier paths.
- Inputs should include the KEL/event bundle and the on-chain anchor trail needed for replay.
- Errors should be deterministic and serializable, matching the existing `Either VerifyError a` style.
- Any crypto dependency for CESR/KERI replay must be WASM/JS-buildable, or isolated behind a target-compatible implementation.

The chain enforces local authorization at mutation time. The reader verifies historical and semantic truth: that the owner key-state was really reached by the KEL and that the two MPFs are complete and mutually consistent.

## 7. Migration and compatibility

This is a breaking validator and wire-format change.

- `State` changes from five fields to at least six fields.
- `OnChainTokenState` in `cardano-mpfs-cage` and both cage transaction clients must change.
- `RequestAction.UpdateAction(Proof)` becomes a larger structure carrying value proof plus owner auth/proof.
- Request datums gain owner auth payloads.
- Existing `verifyStateRootBinding` logic expects the old datum shape and must be versioned.

Existing cages cannot be made trustlessly owned after the fact unless ownership was already encoded in their values and every leaf can be checked. A migration that carries over a non-empty `value_root` and invents an `owners_root` cannot be fully verified on-chain without enumerating the entire trie, which is infeasible. Practical options:

- New cages only: cleanest and safest.
- Trusted migration manifest: off-chain enumerates all old leaves and builds an owners root; readers accept it only if they trust or independently verify the manifest.
- Legacy freeze: migrate old value root with empty owners root and allow only owner-claim operations before future mutation. Existing leaves are not fully protected until claimed.
- A-hybrid migration: if old values already contain owner data, build owners root off-chain from those values and let readers verify consistency. The chain still cannot check the whole map in one transaction.

Execution budget and size:

- The MPF library's own documentation shows proof size and ex-units are the limiting factor; insert/delete can require two proof checks, and proof size grows with trie size.
- B roughly adds one owners-MPF proof per touched leaf plus one Ed25519 verification. For owner rotation/insert it also updates the owners root.
- Request UTxOs grow by owner cell and signature bytes. Redeemers grow by owner proof bytes.
- Batch sizes will likely need to shrink. The current builder already budgets update redeemers aggressively; V2 should benchmark one request, then small batches, before designing broad workflows.
- Script size increases, but B avoids writing an on-chain parser for owner envelopes inside arbitrary value bytes, which keeps it simpler than A.

## 8. Recommendation

Choose B: parallel owners MPF. It is the only design that cleanly separates user payload bytes from authorization state while preserving MPFS's current proof model. It gives the validator a local, bounded check:

```text
state.owners_root proves current owner key-state for key
current owner key verifies one signature over this mutation
state.value_root proof applies the requested value change
output roots equal the folded roots
```

A is useful as a hybrid only for reader ergonomics: store `owner_cell_hash` or `aid` inside the value payload so a fact is self-describing. The validator should not depend on parsing arbitrary value bytes for ownership if a parallel owners root is available.

Biggest risk: key-state anchoring semantics, not MPF mechanics. The chain can verify only the current signing key in an owner cell. It cannot know that this key is the legitimate current KERI key without the off-chain verifier and an accepted anchor trail. Compromise/recovery semantics remain off-chain unless reduced to a single delegated key or simple on-chain hash commitment.

Prototype order:

1. Add a V2 validator with `value_root` and `owners_root`, no migration, one request per Modify.
2. Implement existing-key Update/Delete with owner inclusion proof plus Ed25519 signature; keep owners root unchanged.
3. Measure ex-units and redeemer sizes for one request and small batches.
4. Add first-claim Insert with owners absence proof and value absence proof.
5. Add owner rotation/transfer as an owners-root update.
6. Extend the pure verifier to reconstruct both roots and check owner-cell/KEL consistency.

Do not start with full KERI rotation semantics on-chain. Start with the bounded signature and owners-root invariant, then let the pure verifier carry KEL replay where it belongs.
